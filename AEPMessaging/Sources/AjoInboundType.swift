//
//  AjoInboundTypes.swift
//  AEPMessaging
//
//  Created by steve benedick on 5/19/23.
//

import Foundation

enum AjoInboundType: String, Codable {
    case nativeAlert = "nativeAlert"
    case feedItem = "feedItem"
}
