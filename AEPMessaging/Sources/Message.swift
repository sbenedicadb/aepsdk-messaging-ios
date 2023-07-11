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
import WebKit

/// Class that contains the definition of an in-app message and controls its tracking via Experience Edge events.
@objc(AEPMessage)
public class Message: NSObject {
    // MARK: - public properties

    /// ID of the `Message`.
    @objc public var id: String

    /// If set to `true` (default), Experience Edge events will automatically be generated when this `Message` is
    /// triggered, displayed, and dismissed.
    @objc public var autoTrack: Bool = true

    /// Points to the message's `WKWebView` instance, if it exists.
    @objc public var view: UIView? {
        if let me = self as? HtmlMessage {
            return me.view
        } else {
            return nil
        }
    }

    // MARK: internal properties

    /// Holds a reference to the class that created this `Message`.  Used for access to tracking code owned by `Messaging`.
    weak var parent: Messaging?

    /// The `Event` that triggered this `Message`.  Primarily used for getting the correct `Configuration` for
    /// access to the AEP Dataset ID.
    var triggeringEvent: Event

    /// Holds XDM data necessary for tracking `Message` interactions with Adobe Journey Optimizer.
    var propositionInfo: PropositionInfo?

    /// Creates a Message object which owns and controls UI and tracking behavior of an In-App Message.
    ///
    /// - Parameters:
    ///   - parent: the `Messaging` object that owns the new `Message`
    ///   - event: the Rules Consequence `Event` that defines the message and contains reporting information
    init(parent: Messaging, event: Event) {
        self.parent = parent
        triggeringEvent = event
        id = event.messageId ?? ""
        super.init()
        
        if event.isCjmIamConsequence {
            let messageSettings = event.getMessageSettings(withParent: self)
            let usingLocalAssets = generateAssetMap()
            fullscreenMessage = ServiceProvider.shared.uiService.createFullscreenMessage?(payload: event.html ?? "",
                                                                                          listener: self,
                                                                                          isLocalImageUsed: usingLocalAssets,
                                                                                          settings: messageSettings) as? FullscreenMessage
            if usingLocalAssets {
                fullscreenMessage?.setAssetMap(assets)
            }
        } else if event.isAjoInboundConsequence, let content = event.content {
            if let jsonData = try? JSONSerialization.data(withJSONObject: content, options: .prettyPrinted) {
                nativeAlert = ServiceProvider.shared.uiService.createNativeAlert(jsonData: jsonData, listener: self, settings: MessageSettings(parent: self))
            }
        }
    }
    
    // MARK: - UI management

    /// Requests that UIServices show the this message.
    /// This method will bypass calling the `shouldShowMessage(:)` method of the `MessagingDelegate` if one exists.
    /// If `autoTrack` is true and the message is shown, calling this method will result
    /// in an "inapp.display" Edge Event being dispatched.
    @objc
    public func show() {
        show(withMessagingDelegateControl: false)
    }

    /// Signals to the UIServices that the message should be dismissed.
    /// If `autoTrack` is true, calling this method will result in an "inapp.dismiss" Edge Event being dispatched.
    /// - Parameter suppressAutoTrack: if set to `true`, the "inapp.dismiss" Edge Event will not be sent regardless
    ///   of the `autoTrack` setting.
    @objc(dismissSuppressingAutoTrack:)
    public func dismiss(suppressAutoTrack: Bool = false) {
        if autoTrack, !suppressAutoTrack {
            track(nil, withEdgeEventType: .inappDismiss)
        }
    }

    // MARK: - Edge Event creation

    /// Generates an Edge Event for the provided `interaction` and `eventType`.
    ///
    /// - Parameters:
    ///   - interaction: a custom `String` value to be recorded in the interaction
    ///   - eventType: the `MessagingEdgeEventType` to be used for the ensuing Edge Event
    @objc(trackInteraction:withEdgeEventType:)
    public func track(_ interaction: String?, withEdgeEventType eventType: MessagingEdgeEventType) {
        parent?.sendPropositionInteraction(withEventType: eventType, andInteraction: interaction, forMessage: self)
    }

    // MARK: - WebView javascript handling

    /// Adds a handler for Javascript messages sent from the message's webview.
    ///
    /// The parameter passed to `handler` will contain the body of the message passed from the webview's Javascript.
    ///
    /// - Parameters:
    ///   - name: the name of the message that should be handled by `handler`
    ///   - handler: the closure to be called with the body of the message passed by the Javascript message
    @objc(handleJavascriptMessage:withHandler:)
    public func handleJavascriptMessage(_ name: String, withHandler handler: @escaping (Any?) -> Void) {
        fullscreenMessage?.handleJavascriptMessage(name, withHandler: handler)
    }

    // MARK: - Internal methods

    /// Requests that UIServices show the this message.
    /// Pass `false` to this method to bypass the `MessagingDelegate` control over showing the message.
    /// - Parameters:
    ///   - withMessagingDelegateControl: if `true`, the `shouldShowMessage(:)` method of `MessagingDelegate` will be called before the message is shown.
    func show(withMessagingDelegateControl callDelegate: Bool) {
        if let alert = nativeAlert {
            alert.show()
        } else if let fullscreen = fullscreenMessage {
            fullscreen.show(withMessagingDelegateControl: callDelegate)
        }
    }

    /// Called when a `Message` is triggered - i.e. it's conditional criteria have been met.
    func trigger() {
        if autoTrack {
            track(nil, withEdgeEventType: .inappTrigger)
        }
    }

    // MARK: - Private methods

    /// Generates a mapping of the message's assets to their representation in local cache.
    ///
    /// This method will iterate through the `remoteAssets` of the triggering event for the message.
    /// In each iteration, it will check to see if there is a corresponding cache entry for the
    /// asset string.  If a match is found, an entry will be made in the `Message`s `assets` dictionary.
    ///
    /// - Returns: `true` if an asset map was generated
    private func generateAssetMap() -> Bool {
        guard let remoteAssetsArray = triggeringEvent.remoteAssets, !remoteAssetsArray.isEmpty else {
            return false
        }

        let cache = Cache(name: MessagingConstants.Caches.CACHE_NAME)
        assets = [:]
        for asset in remoteAssetsArray {
            // check for a matching file in cache and add an entry to the assets map if it exists
            if let cachedAsset = cache.get(key: asset) {
                assets?[asset] = cachedAsset.metadata?[MessagingConstants.Caches.PATH]
            }
        }

        return true
    }
}
