/*
 Copyright 2021 Adobe. All rights reserved.
 This file is licensed to you under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License. You may obtain a copy
 of the License at http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed under
 the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
 OF ANY KIND, either express or implied. See the License for the specific language
 governing permissions and limitations under the License.
 */

@testable import AEPMessaging
import Foundation
import XCTest

class MessagingEdgeEventTypeTests: XCTestCase {
    func testDismiss() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 6)

        // verify
        XCTAssertEqual(value, .dismiss)
        XCTAssertEqual("decisioning.propositionDismiss", value?.toString())
    }

    func testInteract() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 7)

        // verify
        XCTAssertEqual(value, .interact)
        XCTAssertEqual("decisioning.propositionInteract", value?.toString())
    }

    func testTrigger() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 8)

        // verify
        XCTAssertEqual(value, .trigger)
        XCTAssertEqual("decisioning.propositionTrigger", value?.toString())
    }

    func testDisplay() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 9)

        // verify
        XCTAssertEqual(value, .display)
        XCTAssertEqual("decisioning.propositionDisplay", value?.toString())
    }
    
    func testDisqualify() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 10)

        // verify
        XCTAssertEqual(value, .disqualify)
        XCTAssertEqual("decisioning.propositionDisqualify", value?.toString())
    }
    
    func testSuppressDisplay() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 11)

        // verify
        XCTAssertEqual(value, .suppressDisplay)
        XCTAssertEqual("decisioning.propositionSuppressDisplay", value?.toString())
    }

    func testPushApplicationOpened() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 4)

        // verify
        XCTAssertEqual(value, .pushApplicationOpened)
        XCTAssertEqual(MessagingConstants.XDM.Push.EventType.APPLICATION_OPENED, value?.toString())
    }

    func testPushCustomAction() throws {
        // setup
        let value = MessagingEdgeEventType(rawValue: 5)

        // verify
        XCTAssertEqual(value, .pushCustomAction)
        XCTAssertEqual(MessagingConstants.XDM.Push.EventType.CUSTOM_ACTION, value?.toString())
    }
    
    func testInitFromStringDismiss() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "decisioning.propositionDismiss")
        
        // verify
        XCTAssertEqual(.dismiss, value)
    }
    
    func testInitFromStringTrigger() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "decisioning.propositionTrigger")
        
        // verify
        XCTAssertEqual(.trigger, value)
    }
    
    func testInitFromStringDisplay() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "decisioning.propositionDisplay")
        
        // verify
        XCTAssertEqual(.display, value)
    }
    
    func testInitFromStringDisqualify() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "decisioning.propositionDisqualify")
        
        // verify
        XCTAssertEqual(.disqualify, value)
    }
    
    func testInitFromStringSuppressDisplay() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "decisioning.propositionSuppressDisplay")
        
        // verify
        XCTAssertEqual(.suppressDisplay, value)
    }
    
    func testInitFromStringInteract() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "decisioning.propositionInteract")
        
        // verify
        XCTAssertEqual(.interact, value)
    }
    
    func testInitFromStringPushOpen() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "pushTracking.applicationOpened")
        
        // verify
        XCTAssertEqual(.pushApplicationOpened, value)
    }
    
    func testInitFromStringPushCustomAction() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "pushTracking.customAction")
        
        // verify
        XCTAssertEqual(.pushCustomAction, value)
    }
    
    func testInitFromStringInvalid() throws {
        // setup
        let value = MessagingEdgeEventType(fromType: "not a valid type")
        
        // verify
        XCTAssertNil(value)
    }
    
    func testInitFromPropositionEventTypeDismiss() throws {
        // setup
        let value = MessagingEdgeEventType(fromPropositionEventType: "dismiss")
        
        // verify
        XCTAssertEqual(.dismiss, value)
    }
    
    func testInitFromPropositionEventTypeTrigger() throws {
        // setup
        let value = MessagingEdgeEventType(fromPropositionEventType: "trigger")
        
        // verify
        XCTAssertEqual(.trigger, value)
    }
    
    func testInitFromPropositionEventTypeDisplay() throws {
        // setup
        let value = MessagingEdgeEventType(fromPropositionEventType: "display")
        
        // verify
        XCTAssertEqual(.display, value)
    }
    
    func testInitFromPropositionEventTypeInteract() throws {
        // setup
        let value = MessagingEdgeEventType(fromPropositionEventType: "interact")
        
        // verify
        XCTAssertEqual(.interact, value)
    }
    
    func testInitFromPropositionEventTypeDisqualify() throws {
        // setup
        let value = MessagingEdgeEventType(fromPropositionEventType: "disqualify")
        
        // verify
        XCTAssertEqual(.disqualify, value)
    }
    
    func testInitFromPropositionEventTypeSuppressDisplay() throws {
        // setup
        let value = MessagingEdgeEventType(fromPropositionEventType: "suppressDisplay")
        
        // verify
        XCTAssertEqual(.suppressDisplay, value)
    }
    
    func testInitFromPropositionEventTypeDefault() throws {
        // setup
        let value = MessagingEdgeEventType(fromPropositionEventType: "nopenopenope")
        
        // verify
        XCTAssertNil(value)
    }
    
    func testPropEventTypeDismiss() throws {
        XCTAssertEqual("dismiss", MessagingEdgeEventType.dismiss.propositionEventType)
    }
    
    func testPropEventTypeDisqualify() throws {
        XCTAssertEqual("disqualify", MessagingEdgeEventType.disqualify.propositionEventType)
    }
    
    func testPropEventTypeDisplay() throws {
        XCTAssertEqual("display", MessagingEdgeEventType.display.propositionEventType)
    }
    
    func testPropEventTypeInteract() throws {
        XCTAssertEqual("interact", MessagingEdgeEventType.interact.propositionEventType)
    }
    
    func testPropEventTypeTrigger() throws {
        XCTAssertEqual("trigger", MessagingEdgeEventType.trigger.propositionEventType)
    }
    
    func testPropEventTypeSuppressDisplay() throws {
        XCTAssertEqual("suppressDisplay", MessagingEdgeEventType.suppressDisplay.propositionEventType)
    }
    
    func testPropEventTypePushCases() throws {
        XCTAssertEqual("", MessagingEdgeEventType.pushCustomAction.propositionEventType)
        XCTAssertEqual("", MessagingEdgeEventType.pushApplicationOpened.propositionEventType)
    }
}
