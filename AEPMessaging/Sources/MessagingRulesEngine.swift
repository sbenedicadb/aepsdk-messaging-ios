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

import AEPCore
import AEPServices
import Foundation

/// Wrapper class around `LaunchRulesEngine` that provides a different implementation for loading rules
class MessagingRulesEngine {
    let rulesEngine: LaunchRulesEngine
    let runtime: ExtensionRuntime
    let cache: Cache
    var inMemoryPropositions: [PropositionPayload] = []
    var propositionInfo: [String: PropositionInfo] = [:]

    /// Initialize this class, creating a new rules engine with the provided name and runtime
    init(name: String, extensionRuntime: ExtensionRuntime) {
        runtime = extensionRuntime
        rulesEngine = LaunchRulesEngine(name: name,
                                        extensionRuntime: extensionRuntime)
        cache = Cache(name: MessagingConstants.Caches.CACHE_NAME)
    }

    /// INTERNAL ONLY
    /// Initializer to provide a mock rules engine for testing
    init(extensionRuntime: ExtensionRuntime, rulesEngine: LaunchRulesEngine, cache: Cache) {
        runtime = extensionRuntime
        self.rulesEngine = rulesEngine
        self.cache = cache
    }

    /// if we have rules loaded, then we simply process the event.
    /// if rules are not yet loaded, add the event to the waitingEvents array to
    func process(event: Event) {
        _ = rulesEngine.process(event: event)
    }

    func loadPropositions(_ propositions: [PropositionPayload]?, clearExisting: Bool, persistChanges: Bool = true, expectedScope: String) {
        
        let decoder = JSONDecoder()
        let testPayload = try! decoder.decode(PropositionPayload.self, from: PROP_PAYLOAD_JSON.data(using: .utf8)!)
                
        var rules: [LaunchRule] = []
        var tempPropInfo: [String: PropositionInfo] = [:]

        if let propositions = propositions {
            for proposition in [testPayload] {
//            for proposition in propositions {
                guard expectedScope == proposition.propositionInfo.scope else {
                    Log.debug(label: MessagingConstants.LOG_TAG, "Ignoring proposition where scope (\(proposition.propositionInfo.scope)) does not match expected scope (\(expectedScope)).")
                    continue
                }

                guard let ruleString = proposition.items.first?.data.content, !ruleString.isEmpty else {
                    Log.debug(label: MessagingConstants.LOG_TAG, "Skipping proposition with no in-app message content.")
                    continue
                }

                guard let rule = processRule(ruleString) else {
                    Log.debug(label: MessagingConstants.LOG_TAG, "Skipping proposition with malformed in-app message content.")
                    continue
                }

                // pre-fetch the assets for this message if there are any defined
                cacheRemoteAssetsFor(rule)

                // store reporting data for this payload for later use
                if let messageId = rule.first?.consequences.first?.id {
                    tempPropInfo[messageId] = proposition.propositionInfo
                }

                rules.append(contentsOf: rule)
            }
        }

        if clearExisting {
            inMemoryPropositions.removeAll()
            cachePropositions(nil)
            propositionInfo = tempPropInfo
            rulesEngine.replaceRules(with: rules)
            Log.debug(label: MessagingConstants.LOG_TAG, "Successfully loaded \(rules.count) message(s) into the rules engine for scope '\(expectedScope)'.")
        } else if !rules.isEmpty {
            propositionInfo.merge(tempPropInfo) { _, new in new }
            rulesEngine.addRules(rules)
            Log.debug(label: MessagingConstants.LOG_TAG, "Successfully added \(rules.count) message(s) into the rules engine for scope '\(expectedScope)'.")
        } else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Ignoring request to load in-app messages for scope '\(expectedScope)'. The propositions parameter provided was empty.")
        }

        if persistChanges {
            addPropositionsToCache(propositions)
        } else {
            inMemoryPropositions.append(contentsOf: propositions ?? [])
        }
    }

    func processRule(_ rule: String) -> [LaunchRule]? {
        JSONRulesParser.parse(rule.data(using: .utf8) ?? Data(), runtime: runtime)
    }

    func propositionInfoForMessageId(_ messageId: String) -> PropositionInfo? {
        propositionInfo[messageId]
    }

    #if DEBUG
        /// For testing purposes only
        internal func propositionInfoCount() -> Int {
            propositionInfo.count
        }

        /// For testing purposes only
        internal func inMemoryPropositionsCount() -> Int {
            inMemoryPropositions.count
        }
    #endif
    
    private let PROP_PAYLOAD_JSON = """
{
    "id": "0b28c7c1-ed3b-4bbb-b2b8-eb79349b5eed",
    "scope": "mobileapp://com.adobe.MessagingDemoApp",
    "scopeDetails": {
        "decisionProvider": "AJO",
        "correlationID": "1016bc82-e60e-4868-8908-782e4de72ba9",
        "characteristics": {
            "eventToken": "eyJtZXNzYWdlRXhlY3V0aW9uIjp7Im1lc3NhZ2VFeGVjdXRpb25JRCI6Ik5BIiwibWVzc2FnZUlEIjoiMTAxNmJjODItZTYwZS00ODY4LTg5MDgtNzgyZTRkZTcyYmE5IiwibWVzc2FnZVB1YmxpY2F0aW9uSUQiOiIxN2U2OTIzZC0yNjZiLTRmZTItYjVhMi1iZWVhMWEyMzY2Y2IiLCJtZXNzYWdlVHlwZSI6Im1hcmtldGluZyIsImNhbXBhaWduSUQiOiJhMWYwZjRiMC1lOTA0LTRlZjgtYWUyZi05MGU3NDhiMzJiM2QiLCJjYW1wYWlnblZlcnNpb25JRCI6IjMxMDczZDM3LTA4NzAtNGE1Yi05NjYxLTY2MDdkOGQ1NGRkZCIsImNhbXBhaWduQWN0aW9uSUQiOiJkYjc4MWQ1My04ZTc1LTQ1NTMtOWY4Mi02ZGU1YjFiY2U4NWEifSwibWVzc2FnZVByb2ZpbGUiOnsibWVzc2FnZVByb2ZpbGVJRCI6ImRlZDA4OTljLTBjYjctNGU0Ny1hNzZhLWU4NjkwNTkzZDU4NSIsImNoYW5uZWwiOnsiX2lkIjoiaHR0cHM6Ly9ucy5hZG9iZS5jb20veGRtL2NoYW5uZWxzL2luQXBwIiwiX3R5cGUiOiJodHRwczovL25zLmFkb2JlLmNvbS94ZG0vY2hhbm5lbC10eXBlcy9pbkFwcCJ9fX0="
        },
        "activity": {
            "id": "a1f0f4b0-e904-4ef8-ae2f-90e748b32b3d#db781d53-8e75-4553-9f82-6de5b1bce85a"
        }
    },
    "items": [
        {
            "id": "2d422dba-2801-4a02-b203-2b3a020133b0",
            "schema": "https://ns.adobe.com/personalization/json-content-item",
            "data": {
                "id": "f1c34f2f-defb-4c6f-8c59-e93696e2c536",
                "content": "{\\\"version\\\":1,\\\"rules\\\":[{\\\"condition\\\":{\\\"definition\\\":{\\\"conditions\\\":[{\\\"definition\\\":{\\\"conditions\\\":[{\\\"definition\\\":{\\\"key\\\":\\\"~type\\\",\\\"matcher\\\":\\\"eq\\\",\\\"values\\\":[\\\"com.adobe.eventType.generic.track\\\"]},\\\"type\\\":\\\"matcher\\\"},{\\\"definition\\\":{\\\"key\\\":\\\"~source\\\",\\\"matcher\\\":\\\"eq\\\",\\\"values\\\":[\\\"com.adobe.eventSource.requestContent\\\"]},\\\"type\\\":\\\"matcher\\\"},{\\\"definition\\\":{\\\"key\\\":\\\"action\\\",\\\"matcher\\\":\\\"ex\\\"},\\\"type\\\":\\\"matcher\\\"}],\\\"logic\\\":\\\"and\\\"},\\\"type\\\":\\\"group\\\"},{\\\"definition\\\":{\\\"key\\\":\\\"action\\\",\\\"matcher\\\":\\\"eq\\\",\\\"values\\\":[\\\"nativeAlert\\\"]},\\\"type\\\":\\\"matcher\\\"}],\\\"logic\\\":\\\"and\\\"},\\\"type\\\":\\\"group\\\"},\\\"consequences\\\":[{\\\"id\\\":\\\"d5af3561-b631-4899-812d-b2af83656729\\\",\\\"type\\\":\\\"ajoInbound\\\",\\\"detail\\\":{\\\"type\\\":\\\"nativeAlert\\\",\\\"expiryDate\\\":1715976625000,\\\"contentType\\\":\\\"application/json\\\",\\\"content\\\":{\\\"title\\\":\\\"App update available!\\\",\\\"message\\\":\\\"Download the new version of the app to use all the cool features.\\\",\\\"defaultButton\\\":\\\"OK\\\",\\\"defaultButtonUrl\\\":\\\"https://adobe.com\\\",\\\"cancelButton\\\":\\\"Not now...\\\",\\\"style\\\":\\\"alert\\\"},\\\"meta\\\":{\\\"metaKey\\\":\\\"metaValue\\\"}}}]}]}"
            }
        }
    ]
}
"""
}
