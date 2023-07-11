//
//  Alert.swift
//  AEPMessaging
//
//  Created by steve benedick on 5/19/23.
//

import Foundation
import AEPServices

class Alert : Message { //}, Trackable {
    var nativeAlert: NativeAlert?
//    var propositionInfo: PropositionInfo?
//    var messagingExtension: Messaging?
//    override func track(interaction: String?, withEdgeEventType eventType: MessagingEdgeEventType) {
//
//    }
    
    init(_ ajoContent: AjoInboundConsequence) {
        // initialize an Alert from the AjoInboundConsequence
        super.init(parent: <#T##Messaging#>, event: <#T##Event#>)
    }
}
