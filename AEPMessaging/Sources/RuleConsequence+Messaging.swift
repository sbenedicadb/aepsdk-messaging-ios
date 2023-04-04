//
//  RuleConsequence+Messaging.swift
//  AEPMessaging
//
//  Created by steve benedick on 4/4/23.
//

import Foundation
import AEPCore

extension RuleConsequence {
    var isFeedItem: Bool {
        guard let mobileParams = details["mobileParameters"] as? [String: Any] else {
            return false
        }
        
        guard let type = mobileParams["type"] as? String else {
            return false
        }
        
        return type == "messagefeed"
    }
}
