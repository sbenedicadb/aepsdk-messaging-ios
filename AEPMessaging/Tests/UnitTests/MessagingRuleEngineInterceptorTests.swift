/*
 Copyright 2024 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

@testable import AEPCore
@testable import AEPMessaging
@testable import AEPRulesEngine
import AEPServices
import AEPTestUtils
import XCTest

class MessagingRuleEngineInterceptorTests: XCTestCase {
    
    var interceptor: MessagingRuleEngineInterceptor!
    var mockRuntime: TestableExtensionRuntime!
    var mockLaunchRulesEngine: MockLaunchRulesEngine!
    var mockMessagingRulesEngine: MockMessagingRulesEngine!
    var mockContentCardRulesEngine: MockContentCardRulesEngine!
    var mockCache: MockCache!
    var messaging: Messaging!
    
    override func setUp() {
        super.setUp()
        EventHub.shared.start()
        RefreshInAppHandler.shared.reset()
        interceptor = MessagingRuleEngineInterceptor()
        mockRuntime = TestableExtensionRuntime()
        mockCache = MockCache(name: "mockCache")
        mockLaunchRulesEngine = MockLaunchRulesEngine(name: "mockLaunchRulesEngine", extensionRuntime: mockRuntime)
        mockMessagingRulesEngine = MockMessagingRulesEngine(extensionRuntime: mockRuntime, launchRulesEngine: mockLaunchRulesEngine, cache: mockCache)
        mockContentCardRulesEngine = MockContentCardRulesEngine(extensionRuntime: mockRuntime, launchRulesEngine: mockLaunchRulesEngine)
    }
    
    override func tearDown() {
        RefreshInAppHandler.shared.reset()
        interceptor = nil
        mockRuntime = nil
        mockLaunchRulesEngine = nil
        mockMessagingRulesEngine = nil
        mockContentCardRulesEngine = nil
        mockCache = nil
        messaging = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    func createTestEvent(name: String = "Test Event") -> Event {
        return Event(name: name, type: EventType.genericTrack, source: EventSource.requestContent, data: nil)
    }
    
    func createTestRule() -> LaunchRule {
        let consequence = RuleConsequence(id: "testConsequence", type: "schema", details: [:])
        let condition = ComparisonExpression(lhs: "true", operationName: "equals", rhs: "true")
        return LaunchRule(condition: condition, consequences: [consequence])
    }
    
    // MARK: - Messaging Extension Interceptor Registration Tests
    
    func testMessagingInit_registersReevaluationInterceptor() {
        // Setup & Test
        let stateManager = MessagingStateManager()
        messaging = Messaging(runtime: mockRuntime,
                             rulesEngine: mockMessagingRulesEngine,
                             contentCardRulesEngine: mockContentCardRulesEngine,
                             expectedSurfaceUri: "mobileapp://test",
                             cache: mockCache,
                             stateManager: stateManager)
        
        // Verify - the interceptor should be set on the launch rules engine
        XCTAssertTrue(mockLaunchRulesEngine.setReevaluationInterceptorCalled,
                      "setReevaluationInterceptor should be called during Messaging initialization")
        XCTAssertNotNil(mockLaunchRulesEngine.paramReevaluationInterceptor,
                        "Reevaluation interceptor should not be nil")
    }
    
    func testMessagingInit_interceptorIsCorrectType() {
        // Setup & Test
        let stateManager = MessagingStateManager()
        messaging = Messaging(runtime: mockRuntime,
                             rulesEngine: mockMessagingRulesEngine,
                             contentCardRulesEngine: mockContentCardRulesEngine,
                             expectedSurfaceUri: "mobileapp://test",
                             cache: mockCache,
                             stateManager: stateManager)
        
        // Verify
        guard let interceptor = mockLaunchRulesEngine.paramReevaluationInterceptor else {
            XCTFail("Interceptor should be set")
            return
        }
        
        XCTAssertTrue(interceptor is MessagingRuleEngineInterceptor,
                      "Registered interceptor should be MessagingRuleEngineInterceptor")
    }
    
    func testInterceptorConformsToRuleReevaluationInterceptor() {
        // Verify the interceptor conforms to the protocol
        XCTAssertTrue(interceptor is RuleReevaluationInterceptor,
                      "MessagingRuleEngineInterceptor should conform to RuleReevaluationInterceptor")
    }
    
    // MARK: - Single Request Tests
    
    func testOnReevaluationTriggered_singleRequest_completionCalledOnSuccess() {
        // Setup
        let completionExpectation = expectation(description: "Completion should be called")
        var receivedSuccess: Bool?
        
        let event = createTestEvent()
        let rule = createTestRule()
        
        // Test
        interceptor.onReevaluationTriggered(event: event, reevaluableRules: [rule]) { success in
            receivedSuccess = success
            completionExpectation.fulfill()
        }
        
        // Simulate successful refresh via RefreshInAppHandler
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            RefreshInAppHandler.shared.handleRefreshComplete(success: true)
        }
        
        // Verify
        wait(for: [completionExpectation], timeout: 2.0)
        XCTAssertEqual(receivedSuccess, true, "Completion should receive success")
    }
    
    func testOnReevaluationTriggered_singleRequest_completionCalledOnFailure() {
        // Setup
        let completionExpectation = expectation(description: "Completion should be called")
        var receivedSuccess: Bool?
        
        let event = createTestEvent()
        let rule = createTestRule()
        
        // Test
        interceptor.onReevaluationTriggered(event: event, reevaluableRules: [rule]) { success in
            receivedSuccess = success
            completionExpectation.fulfill()
        }
        
        // Simulate failed refresh via RefreshInAppHandler
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            RefreshInAppHandler.shared.handleRefreshComplete(success: false)
        }
        
        // Verify
        wait(for: [completionExpectation], timeout: 2.0)
        XCTAssertEqual(receivedSuccess, false, "Completion should receive failure")
    }
    
    // MARK: - Queueing Behavior Tests (via RefreshInAppHandler)
    
    func testOnReevaluationTriggered_multipleRequests_queuesCompletions() {
        // Setup
        let completion1Expectation = expectation(description: "Completion 1 should be called")
        let completion2Expectation = expectation(description: "Completion 2 should be called")
        let completion3Expectation = expectation(description: "Completion 3 should be called")
        
        var results: [Bool] = []
        let resultsLock = NSLock()
        
        let event1 = createTestEvent(name: "Event 1")
        let event2 = createTestEvent(name: "Event 2")
        let event3 = createTestEvent(name: "Event 3")
        let rule = createTestRule()
        
        // Test - trigger multiple requests quickly (RefreshInAppHandler queues them)
        interceptor.onReevaluationTriggered(event: event1, reevaluableRules: [rule]) { success in
            resultsLock.lock()
            results.append(success)
            resultsLock.unlock()
            completion1Expectation.fulfill()
        }
        
        // Allow first request to start
        Thread.sleep(forTimeInterval: 0.05)
        
        interceptor.onReevaluationTriggered(event: event2, reevaluableRules: [rule]) { success in
            resultsLock.lock()
            results.append(success)
            resultsLock.unlock()
            completion2Expectation.fulfill()
        }
        
        interceptor.onReevaluationTriggered(event: event3, reevaluableRules: [rule]) { success in
            resultsLock.lock()
            results.append(success)
            resultsLock.unlock()
            completion3Expectation.fulfill()
        }
        
        // Wait a bit for all requests to be queued
        Thread.sleep(forTimeInterval: 0.1)
        
        // Complete the refresh - all queued completions should receive this result
        RefreshInAppHandler.shared.handleRefreshComplete(success: true)
        
        // Verify
        wait(for: [completion1Expectation, completion2Expectation, completion3Expectation], timeout: 2.0)
        XCTAssertEqual(results.count, 3, "All 3 completions should be called")
        XCTAssertTrue(results.allSatisfy { $0 == true }, "All completions should receive success")
    }
    
    func testOnReevaluationTriggered_multipleRequests_allReceiveFailure() {
        // Setup
        let completion1Expectation = expectation(description: "Completion 1 should be called")
        let completion2Expectation = expectation(description: "Completion 2 should be called")
        
        var results: [Bool] = []
        let resultsLock = NSLock()
        
        let event1 = createTestEvent(name: "Event 1")
        let event2 = createTestEvent(name: "Event 2")
        let rule = createTestRule()
        
        // Test
        interceptor.onReevaluationTriggered(event: event1, reevaluableRules: [rule]) { success in
            resultsLock.lock()
            results.append(success)
            resultsLock.unlock()
            completion1Expectation.fulfill()
        }
        
        Thread.sleep(forTimeInterval: 0.05)
        
        interceptor.onReevaluationTriggered(event: event2, reevaluableRules: [rule]) { success in
            resultsLock.lock()
            results.append(success)
            resultsLock.unlock()
            completion2Expectation.fulfill()
        }
        
        Thread.sleep(forTimeInterval: 0.1)
        
        // Fail the refresh
        RefreshInAppHandler.shared.handleRefreshComplete(success: false)
        
        // Verify - all completions should receive failure
        wait(for: [completion1Expectation, completion2Expectation], timeout: 2.0)
        XCTAssertEqual(results.count, 2, "Both completions should be called")
        XCTAssertTrue(results.allSatisfy { $0 == false }, "All completions should receive failure")
    }
    
    // MARK: - Sequential Request Tests
    
    func testOnReevaluationTriggered_sequentialRequests_eachCompletesIndependently() {
        // Setup
        let completion1Expectation = expectation(description: "Completion 1 should be called")
        let completion2Expectation = expectation(description: "Completion 2 should be called")
        
        let event1 = createTestEvent(name: "Event 1")
        let event2 = createTestEvent(name: "Event 2")
        let rule = createTestRule()
        
        // Test - trigger first request and wait for completion
        interceptor.onReevaluationTriggered(event: event1, reevaluableRules: [rule]) { _ in
            completion1Expectation.fulfill()
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            RefreshInAppHandler.shared.handleRefreshComplete(success: true)
        }
        
        wait(for: [completion1Expectation], timeout: 2.0)
        
        // Trigger second request after first completes
        interceptor.onReevaluationTriggered(event: event2, reevaluableRules: [rule]) { _ in
            completion2Expectation.fulfill()
        }
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            RefreshInAppHandler.shared.handleRefreshComplete(success: true)
        }
        
        wait(for: [completion2Expectation], timeout: 2.0)
    }
    
    // MARK: - Empty Rules Tests
    
    func testOnReevaluationTriggered_emptyRules_stillTriggersRefresh() {
        // Setup
        let completionExpectation = expectation(description: "Completion should be called")
        
        let event = createTestEvent()
        
        // Test - trigger with empty rules
        interceptor.onReevaluationTriggered(event: event, reevaluableRules: []) { _ in
            completionExpectation.fulfill()
        }
        
        // Simulate completion
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            RefreshInAppHandler.shared.handleRefreshComplete(success: true)
        }
        
        // Verify
        wait(for: [completionExpectation], timeout: 2.0)
    }
    
    // MARK: - Thread Safety Tests
    
    func testOnReevaluationTriggered_concurrentCalls_handledSafely() {
        // Setup
        let concurrentQueue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let completionGroup = DispatchGroup()
        var completionCount = 0
        let countLock = NSLock()
        let numberOfRequests = 10
        
        let rule = createTestRule()
        
        // Test - trigger many concurrent requests
        for i in 0..<numberOfRequests {
            completionGroup.enter()
            concurrentQueue.async {
                let event = self.createTestEvent(name: "Event \(i)")
                self.interceptor.onReevaluationTriggered(event: event, reevaluableRules: [rule]) { _ in
                    countLock.lock()
                    completionCount += 1
                    countLock.unlock()
                    completionGroup.leave()
                }
            }
        }
        
        // Wait for all requests to be submitted
        Thread.sleep(forTimeInterval: 0.2)
        
        // Complete the refresh - RefreshInAppHandler should call all queued completions
        RefreshInAppHandler.shared.handleRefreshComplete(success: true)
        
        // Verify
        let result = completionGroup.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "All completions should be called")
        XCTAssertEqual(completionCount, numberOfRequests, "All \(numberOfRequests) completions should be called")
    }
}
