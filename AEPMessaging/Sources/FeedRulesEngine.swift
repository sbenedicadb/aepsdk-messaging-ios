//
//  FeedRulesEngine.swift
//  AEPMessaging
//
//  Created by steve benedick on 3/29/23.
//

import Foundation
import AEPCore
import AEPServices
import AEPRulesEngine

class FeedRulesEngine {
    let rulesEngine: LaunchRulesEngine
    let runtime: ExtensionRuntime
    var feeds: [String: Feed] = [:]
    
    /// Initialize this class, creating a new rules engine with the provided name and runtime
    init(name: String, extensionRuntime: ExtensionRuntime) {
        runtime = extensionRuntime
        rulesEngine = LaunchRulesEngine(name: name,
                                        extensionRuntime: extensionRuntime)
    }

    /// INTERNAL ONLY
    /// Initializer to provide a mock rules engine for testing
    init(extensionRuntime: ExtensionRuntime, rulesEngine: LaunchRulesEngine) {
        runtime = extensionRuntime
        self.rulesEngine = rulesEngine
    }

    /// if we have rules loaded, then we simply process the event.
    /// if rules are not yet loaded, add the event to the waitingEvents array to
    func process(event: Event, _ completion: (([String: Feed]?) -> Void)? = nil) {
        rulesEngine.process(event: event) { consequences in
            guard let consequences = consequences else {
                completion?(nil)
                return
            }
            
            for consequence in consequences {
                let details = consequence.details as [String: Any]
                
                if let mobileParams = details["mobileParameters"] as? [String: Any], let feedItem = FeedItem.from(data: mobileParams) {
                    let surface = feedItem.surface
                    let feedName = feedItem.feedName
                    
                    let parent = surface ?? feedName ?? "unknown"
                    
                    if let feed = feeds[parent] {
                        feed.items.append(feedItem)
                    } else {
                        feeds[parent] = Feed(surfaceUri: parent, items: [feedItem])
                    }
                }
            }
            completion?(feeds)
        }
    }

    func loadFeeds(_ feeds: [PropositionPayload]?, clearExisting: Bool, persistChanges: Bool = true) {
                
        var rules: [LaunchRule] = []
        
        if let feeds = feeds {
            for proposition in feeds {
                                
                guard let ruleString = proposition.items.first?.data.content, !ruleString.isEmpty else {
                    Log.debug(label: MessagingConstants.LOG_TAG, "Skipping proposition with no feed content.")
                    continue
                }
                
                guard let processedRules = processRule(ruleString) else {
                    Log.debug(label: MessagingConstants.LOG_TAG, "Skipping proposition with malformed feed content.")
                    continue
                }
                
                // loop through consequences and only add feed items
                for rule in processedRules {
                    var consequenceContainsFeedItem = false
                    
                    for consequence in rule.consequences {
                        if consequence.isFeedItem {
                            consequenceContainsFeedItem = true
                            break
                        }
                    }
                    
                    if consequenceContainsFeedItem {
                        rules.append(rule)
                    }
                }
            }
        }

        if clearExisting {
            rulesEngine.replaceRules(with: rules)
            Log.debug(label: MessagingConstants.LOG_TAG, "Successfully loaded \(rules.count) feed rule(s) into the rules engine.")
        } else if !rules.isEmpty {
            rulesEngine.addRules(rules)
            Log.debug(label: MessagingConstants.LOG_TAG, "Successfully added \(rules.count) feed rule(s) into the rules engine.")
        } else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Ignoring request to load feed rules. The propositions parameter provided was empty.")
        }
    }
    
    private func processRule(_ rule: String) -> [LaunchRule]? {
        return JSONRulesParser.parse(rule.data(using: .utf8) ?? Data(), runtime: runtime)
    }
}
