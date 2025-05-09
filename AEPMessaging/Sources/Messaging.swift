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

@objc(AEPMobileMessaging)
public class Messaging: NSObject, Extension {
    // MARK: - Class members

    public static var extensionVersion: String = MessagingConstants.EXTENSION_VERSION
    public var name = MessagingConstants.EXTENSION_NAME
    public var friendlyName = MessagingConstants.FRIENDLY_NAME
    public var metadata: [String: String]?
    public var runtime: ExtensionRuntime

    // Operation orderer used to maintain the order of update and get propositions events.
    // It ensures any update propositions requests issued before a get propositions call are completed
    // and the get propositions request is fulfilled from the latest cached content.
    private let eventsQueue = OperationOrderer<Event>("MessagingEvents")

    // Queue for completion handlers providing thread-safe read/writing of the `completionHandlers` array
    private static let handlersQueue: DispatchQueue = .init(label: "com.adobe.messaging.completionHandlers.queue")
    private static var _completionHandlers: [CompletionHandler] = []
    static var completionHandlers: [CompletionHandler] {
        get { handlersQueue.sync { self._completionHandlers } }
        set { handlersQueue.async { self._completionHandlers = newValue } }
    }

    // MARK: - Messaging State

    var cache: Cache = .init(name: MessagingConstants.Caches.CACHE_NAME)
    var appSurface: String {
        Bundle.main.mobileappSurface
    }

    private var initialLoadComplete = false
    let rulesEngine: MessagingRulesEngine
    let contentCardRulesEngine: ContentCardRulesEngine

    /// Dispatch queue used to protect against simultaneous access of our containers from multiple threads
    private let queue: DispatchQueue = .init(label: "com.adobe.messaging.containers.queue")

    /// holds in-memory propositions for CBE (json-content, html-content, default-content) and IAM
    private var _inMemoryPropositions: [Surface: [Proposition]] = [:]
    var inMemoryPropositions: [Surface: [Proposition]] {
        get { queue.sync { self._inMemoryPropositions } }
        set { queue.async { self._inMemoryPropositions = newValue } }
    }

    /// propositionInfo stored by RuleConsequence.id
    private var _propositionInfo: [String: PropositionInfo] = [:]
    var propositionInfo: [String: PropositionInfo] {
        get { queue.sync { self._propositionInfo } }
        set { queue.async { self._propositionInfo = newValue } }
    }

    /// keeps a list of all surfaces requested per personalization request event by event id
    private var _requestedSurfacesForEventId: [String: [Surface]] = [:]
    private var requestedSurfacesForEventId: [String: [Surface]] {
        get { queue.sync { self._requestedSurfacesForEventId } }
        set { queue.async { self._requestedSurfacesForEventId = newValue } }
    }

    /// used while processing streaming payloads for a single request
    private var _inProgressPropositions: [Surface: [Proposition]] = [:]
    private var inProgressPropositions: [Surface: [Proposition]] {
        get { queue.sync { self._inProgressPropositions } }
        set { queue.async { self._inProgressPropositions = newValue } }
    }

    private var _inAppRulesBySurface: [Surface: [LaunchRule]] = [:]
    private var inAppRulesBySurface: [Surface: [LaunchRule]] {
        get { queue.sync { self._inAppRulesBySurface } }
        set { queue.async { self._inAppRulesBySurface = newValue } }
    }

    /// used to manage content card rules between multiple surfaces and multiple requests
    private var _contentCardRulesBySurface: [Surface: [LaunchRule]] = [:]
    private var contentCardRulesBySurface: [Surface: [LaunchRule]] {
        get { queue.sync { self._contentCardRulesBySurface } }
        set { queue.async { self._contentCardRulesBySurface = newValue } }
    }

    /// holds content cards that the user has qualified for
    private var _qualifiedContentCardsBySurface: [Surface: [Proposition]] = [:]
    var qualifiedContentCardsBySurface: [Surface: [Proposition]] {
        get { queue.sync { self._qualifiedContentCardsBySurface } }
        set { queue.async { self._qualifiedContentCardsBySurface = newValue } }
    }

    /// Array containing the schema strings for the proposition items supported by the SDK, sent in the personalization query request.
    static let supportedSchemas = [
        MessagingConstants.PersonalizationSchemas.HTML_CONTENT,
        MessagingConstants.PersonalizationSchemas.JSON_CONTENT,
        MessagingConstants.PersonalizationSchemas.RULESET_ITEM
    ]

    // MARK: - Extension protocol methods

    public required init?(runtime: ExtensionRuntime) {
        self.runtime = runtime
        MessagingMigrator.migrate(cache: cache)
        rulesEngine = MessagingRulesEngine(name: MessagingConstants.RULES_ENGINE_NAME, extensionRuntime: runtime, cache: cache)
        contentCardRulesEngine = ContentCardRulesEngine(name: MessagingConstants.CONTENT_CARD_RULES_ENGINE_NAME, extensionRuntime: runtime)
        super.init()
        loadCachedPropositions()
    }

    /// INTERNAL ONLY
    /// used for testing
    init(runtime: ExtensionRuntime, rulesEngine: MessagingRulesEngine, contentCardRulesEngine: ContentCardRulesEngine, expectedSurfaceUri _: String, cache: Cache) {
        self.runtime = runtime
        self.rulesEngine = rulesEngine
        self.contentCardRulesEngine = contentCardRulesEngine
        self.cache = cache
        super.init()
        loadCachedPropositions()
    }

    public func onRegistered() {
        // register listener for set push identifier event
        registerListener(type: EventType.genericIdentity,
                         source: EventSource.requestContent,
                         listener: handleProcessEvent)

        // register listener for Messaging request content event
        registerListener(type: EventType.messaging,
                         source: EventSource.requestContent,
                         listener: handleProcessEvent)

        // register wildcard listener for messaging rules engine
        registerListener(type: EventType.wildcard,
                         source: EventSource.wildcard,
                         listener: handleWildcardEvent)

        // register listener for rules consequences with in-app messages
        registerListener(type: EventType.rulesEngine,
                         source: EventSource.responseContent,
                         listener: handleRulesResponse)

        // register listener for edge personalization notifications
        registerListener(type: EventType.edge,
                         source: MessagingConstants.Event.Source.PERSONALIZATION_DECISIONS,
                         listener: handleEdgePersonalizationNotification)

        // register listener for handling personalization request complete events
        registerListener(type: EventType.messaging,
                         source: EventSource.contentComplete,
                         listener: handleProcessCompletedEvent(_:))

        // register listener for handling debug events
        registerListener(type: EventType.system,
                         source: EventSource.debug,
                         listener: handleDebugEvent)

        // register listener for handling event history write events
        registerListener(type: EventType.messaging,
                         source: MessagingConstants.Event.Source.EVENT_HISTORY_WRITE,
                         listener: handleEventHistoryWrite)

        // Handler function called for each queued event. If the queued event is a get propositions event, process it
        // otherwise if it is an Edge event to update propositions, process it only if it is completed.
        eventsQueue.setHandler { event -> Bool in
            if event.isGetPropositionsEvent {
                self.retrieveMessages(for: event.surfaces ?? [], event: event)
            } else if event.type == EventType.edge {
                return !self.requestedSurfacesForEventId.keys.contains(event.id.uuidString)
            }
            return true
        }
        eventsQueue.start()
    }

    public func onUnregistered() {
        Log.debug(label: MessagingConstants.LOG_TAG, "Extension unregistered from MobileCore: \(MessagingConstants.FRIENDLY_NAME)")
    }

    public func readyForEvent(_ event: Event) -> Bool {
        guard let configurationSharedState = getSharedState(extensionName: MessagingConstants.SharedState.Configuration.NAME, event: event),
              configurationSharedState.status == .set
        else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Event processing is paused - waiting for valid configuration.")
            return false
        }

        // hard dependency on edge identity module for ecid
        guard let edgeIdentitySharedState = getXDMSharedState(extensionName: MessagingConstants.SharedState.EdgeIdentity.NAME, event: event),
              edgeIdentitySharedState.status == .set
        else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Event processing is paused - waiting for valid XDM shared state from Edge Identity extension.")
            return false
        }

        // once we have valid configuration, fetch message definitions from offers if we haven't already
        if !initialLoadComplete {
            initialLoadComplete = true
            fetchPropositions(event)
        }

        return true
    }

    // MARK: - Event Handers

    /// Processes the events in the event queue in the order they were received.
    ///
    /// A valid `Configuration` and `EdgeIdentity` shared state is required for processing events.
    ///
    /// - Parameters:
    ///   - event: An `Event` to be processed
    func handleProcessEvent(_ event: Event) {
        guard event.data != nil else {
            Log.debug(label: MessagingConstants.LOG_TAG, "Process event handling ignored as event does not have any data - `\(event.id)`.")
            return
        }

        // hard dependency on configuration shared state
        guard getSharedState(extensionName: MessagingConstants.SharedState.Configuration.NAME, event: event)?.value != nil else {
            Log.debug(label: MessagingConstants.LOG_TAG, "Event processing is paused, waiting for valid configuration - '\(event.id.uuidString)'.")
            return
        }

        // handle an event to request propositions from the remote
        if event.isUpdatePropositionsEvent {
            Log.debug(label: MessagingConstants.LOG_TAG, "Processing request to update propositions from the remote.")
            fetchPropositions(event, for: event.surfaces ?? [])
            return
        }

        // handle an event to get cached propositions from the SDK
        if event.isGetPropositionsEvent {
            Log.debug(label: MessagingConstants.LOG_TAG, "Processing request to get message propositions cached in the SDK.")
            // Queue the get propositions event in internal events queue to ensure any prior update requests are completed
            // before it is processed.
            eventsQueue.add(event)
            return
        }

        // handle an event to track propositions
        if event.isTrackPropositionsEvent {
            Log.debug(label: MessagingConstants.LOG_TAG, "Processing request to track propositions.")
            trackMessages(event)
            return
        }

        // handle an event for refreshing in-app messages from the remote
        if event.isRefreshMessageEvent {
            Log.debug(label: MessagingConstants.LOG_TAG, "Processing manual request to refresh In-App Message definitions from the remote.")
            fetchPropositions(event)
            return
        }

        // hard dependency on edge identity module for ecid
        guard let edgeIdentitySharedState = getXDMSharedState(extensionName: MessagingConstants.SharedState.EdgeIdentity.NAME, event: event)?.value else {
            Log.debug(label: MessagingConstants.LOG_TAG, "Event processing is paused, for valid xdm shared state from edge identity - '\(event.id.uuidString)'.")
            return
        }

        if event.isGenericIdentityRequestContentEvent {
            guard let token = event.token, !token.isEmpty else {
                Log.debug(label: MessagingConstants.LOG_TAG, "Ignoring event with missing or invalid push identifier - '\(event.id.uuidString)'.")
                return
            }

            // If the push token is valid update the shared state.
            runtime.createSharedState(data: [MessagingConstants.SharedState.Messaging.PUSH_IDENTIFIER: token], event: event)

            // get identityMap from the edge identity xdm shared state
            guard let identityMap = edgeIdentitySharedState[MessagingConstants.SharedState.EdgeIdentity.IDENTITY_MAP] as? [AnyHashable: Any] else {
                Log.warning(label: MessagingConstants.LOG_TAG, "Cannot process event that identity map is not available" +
                    "from edge identity xdm shared state - '\(event.id.uuidString)'.")
                return
            }

            // get the ECID array from the identityMap
            guard let ecidArray = identityMap[MessagingConstants.SharedState.EdgeIdentity.ECID] as? [[AnyHashable: Any]],
                  !ecidArray.isEmpty, let ecid = ecidArray[0][MessagingConstants.SharedState.EdgeIdentity.ID] as? String,
                  !ecid.isEmpty
            else {
                Log.warning(label: MessagingConstants.LOG_TAG, "Cannot process event as ecid is not available in the identity map - '\(event.id.uuidString)'.")
                return
            }

            sendPushToken(ecid: ecid, token: token, event: event)
        }

        // Check if the event type is `MessagingConstants.Event.EventType.messaging` and
        // eventSource is `EventSource.requestContent` handle processing of the tracking information
        if event.isMessagingRequestContentEvent {
            if let clickThroughUrl = event.pushClickThroughUrl {
                DispatchQueue.main.async {
                    ServiceProvider.shared.urlService.openUrl(clickThroughUrl)
                }
            }
            handleTrackingInfo(event: event)
            return
        }
    }

    /// Responds to event history write events.
    /// Only current requirement is to remove cached content cards on a disqualify write
    func handleEventHistoryWrite(_ event: Event) {
        guard event.isDisqualifyEvent, let activityId = event.eventHistoryActivityId else {
            return
        }

        removePropositionFromQualifiedCards(for: activityId)
    }

    // MARK: - In-app Messaging methods

    /// Processes debug events triggered by the system.
    /// A debug event allows the messaging extension to processes non-production workflows.
    /// - Parameter event: the debug `Event` to be handled.
    private func handleDebugEvent(_ event: Event) {
        // handle rules consequence debug events
        if event.debugEventType == EventType.rulesEngine, event.debugEventSource == EventSource.responseContent {
            // we can only handle schema consequences
            guard event.isSchemaConsequence, event.data != nil else {
                Log.trace(label: MessagingConstants.LOG_TAG, "Ignoring rule consequence event. Either consequence is not of type 'schema' or 'eventData' is nil.")
                return
            }

            // create a temporary proposition item
            guard let temporaryPropositionItem = PropositionItem.fromRuleConsequenceEvent(event) else {
                return
            }

            switch temporaryPropositionItem.schema {
            case .inapp:
                if
                    let message = Message.fromPropositionItem(temporaryPropositionItem, with: self, triggeringEvent: event) {
                    message.trigger()
                    message.show(withMessagingDelegateControl: true)
                }
            default:
                return
            }
        }
    }

    /// Called on every event, used to allow processing of the Messaging rules engine
    private func handleWildcardEvent(_ event: Event) {
        rulesEngine.process(event: event)

        let qualifiedContentCardsBySurface = getPropositionsFromContentCardRulesEngine(event)
        for (surface, propositions) in qualifiedContentCardsBySurface {
            addOrReplaceContentCards(propositions, forSurface: surface)
        }
    }

    /// Prevents multiple propositions from being in `qualifiedContentCardsBySurface` at the same time
    /// If an existing entry for a proposition is found, it is replaced with the value in `propositions`.
    /// If no prior entry exists for a proposition, a `trigger` event will be sent (and written to event history).
    private func addOrReplaceContentCards(_ propositions: [Proposition], forSurface surface: Surface) {
        let startingCount = qualifiedContentCardsBySurface[surface]?.count ?? 0
        if var existingPropositionsArray = qualifiedContentCardsBySurface[surface] {
            for proposition in propositions {
                if let index = existingPropositionsArray.firstIndex(of: proposition) {
                    existingPropositionsArray.remove(at: index)
                } else {
                    proposition.items.first?.track(withEdgeEventType: .trigger)
                }

                existingPropositionsArray.append(proposition)
            }
            qualifiedContentCardsBySurface[surface] = existingPropositionsArray
        } else {
            for proposition in propositions {
                proposition.items.first?.track(withEdgeEventType: .trigger)
            }
            qualifiedContentCardsBySurface[surface] = propositions
        }

        let cardCount = qualifiedContentCardsBySurface[surface]?.count ?? 0
        if startingCount != cardCount {
            if cardCount > 0 {
                Log.trace(label: MessagingConstants.LOG_TAG, "User has qualified for \(cardCount) content card(s) for surface \(surface.uri).")
            } else {
                Log.trace(label: MessagingConstants.LOG_TAG, "User has not qualified for any content cards for surface \(surface.uri).")
            }
        }
    }

    /// Removes the `Proposition` from `qualifiedContentCardsBySurface` based on provided `activityId`.
    ///
    /// - Parameter activityId: the activityId of the `Proposition` to be removed from cache.
    private func removePropositionFromQualifiedCards(for activityId: String) {
        // find the matching proposition in `qualifiedContentCardsBySurface`
        for (surface, propositions) in qualifiedContentCardsBySurface {
            if let matchedProposition = propositions.filter({ $0.activityId == activityId }).first,
               let index = propositions.firstIndex(of: matchedProposition) {
                // we found the matching proposition - remove it from our cache
                qualifiedContentCardsBySurface[surface]?.remove(at: index)
                return
            }
        }
    }

    /// Generates and dispatches an event prompting the Edge extension to fetch propositions (in-app, content cards, or code-based experiences).
    ///
    /// The surface URIs used in the request are generated using the `bundleIdentifier` for the app.
    /// If the `bundleIdentifier` is unavailable, calling this method will do nothing.
    ///
    /// - Parameters:
    ///   - event - parent event requesting that the messages be fetched. Used for event chaining to help with debugging.
    ///   - surfaces: an array of surface path strings for fetching propositions, if available.
    private func fetchPropositions(_ event: Event, for surfaces: [Surface]? = nil) {
        // check for completion handler for requesting event
        let handler = completionHandlerFor(originatingEventId: event.id)

        var requestedSurfaces: [Surface] = []

        // if surfaces are provided, use them - otherwise assume the request is for base surface (mobileapp://{bundle identifier})
        if let surfaces = surfaces {
            requestedSurfaces = surfaces.filter { $0.isValid }

            guard !requestedSurfaces.isEmpty else {
                Log.debug(label: MessagingConstants.LOG_TAG, "Unable to update messages, no valid surfaces found.")
                handler?.handle?(false)
                return
            }
        } else {
            guard appSurface != "unknown" else {
                Log.warning(label: MessagingConstants.LOG_TAG, "Unable to update messages, cannot read the bundle identifier.")
                handler?.handle?(false)
                return
            }
            requestedSurfaces = [Surface(uri: appSurface)]
        }

        // begin construction of event data
        var eventData: [String: Any] = [:]

        // add `query` parameters containing supported schemas and requested surfaces
        eventData[MessagingConstants.XDM.Inbound.Key.QUERY] = [
            MessagingConstants.XDM.Inbound.Key.PERSONALIZATION: [
                MessagingConstants.XDM.Inbound.Key.SCHEMAS: Messaging.supportedSchemas,
                MessagingConstants.XDM.Inbound.Key.SURFACES: requestedSurfaces.compactMap { $0.uri }
            ]
        ]

        // add `xdm` with an event type of `personalization.request`
        eventData[MessagingConstants.XDM.Key.XDM] = [
            MessagingConstants.XDM.Key.EVENT_TYPE: MessagingConstants.XDM.Inbound.EventType.PERSONALIZATION_REQUEST
        ]

        // add a `data` object to the request specifying the format desired in the response from XAS
        eventData[MessagingConstants.Event.Data.Key.DATA] = [
            MessagingConstants.Event.Data.AdobeKeys.NAMESPACE: [
                MessagingConstants.Event.Data.AdobeKeys.AJO: [
                    MessagingConstants.Event.Data.AdobeKeys.INAPP_RESPONSE_FORMAT: MessagingConstants.XDM.Inbound.Value.IAM_RESPONSE_FORMAT
                ]
            ]
        ]

        // add a `request` object so we get a response event from edge when the propositions stream is closed for this event
        eventData[MessagingConstants.XDM.Key.REQUEST] = [
            MessagingConstants.XDM.Key.SEND_COMPLETION: true
        ]
        // end construction of event data

        let newEvent = event.createChainedEvent(name: MessagingConstants.Event.Name.RETRIEVE_MESSAGE_DEFINITIONS,
                                                type: EventType.edge,
                                                source: EventSource.requestContent,
                                                data: eventData)

        // create entries in our local containers for managing streamed responses from edge
        beginRequestFor(newEvent, with: requestedSurfaces)

        if var handler = handler {
            handler.edgeRequestEventId = newEvent.id
            Messaging.completionHandlers.append(handler)
        }

        // dispatch the event and implement handler for the completion event
        MobileCore.dispatch(event: newEvent, timeout: 10.0) { responseEvent in
            // responseEvent is the event dispatched by Edge extension when a request's stream has been closed
            guard let responseEvent = responseEvent,
                  let endingEventId = responseEvent.requestEventId
            else {
                // response event failed or timed out, need to remove this event from the queue
                self.requestedSurfacesForEventId.removeValue(forKey: newEvent.id.uuidString)
                self.eventsQueue.start()

                Log.warning(label: MessagingConstants.LOG_TAG, "Unable to run completion logic for a personalization request event - unable to obtain parent event ID")
                return
            }

            // dispatch an event signaling messaging extension needs to finalize this event
            // it must be dispatched to the event queue to avoid a race with the events containing propositions
            let processCompletedEvent = responseEvent.createChainedEvent(name: MessagingConstants.Event.Name.FINALIZE_PROPOSITIONS_RESPONSE,
                                                                         type: EventType.messaging,
                                                                         source: EventSource.contentComplete,
                                                                         data: [MessagingConstants.Event.Data.Key.ENDING_EVENT_ID: endingEventId])
            self.dispatch(event: processCompletedEvent)
        }
    }

    func handleProcessCompletedEvent(_ event: Event) {
        defer {
            // kick off processing the internal events queue after processing is completed for an update propositions request
            eventsQueue.start()
        }

        guard let endingEventId = event.data?[MessagingConstants.Event.Data.Key.ENDING_EVENT_ID] as? String,
              let requestedSurfaces = requestedSurfacesForEventId[endingEventId]
        else {
            // shouldn't ever get here, but if we do, we don't have anything to process so we should bail
            return
        }

        Log.trace(label: MessagingConstants.LOG_TAG, "End of streaming response events for requesting event '\(endingEventId)'")
        endRequestFor(eventId: endingEventId)

        // dispatch notification event for request
        dispatchNotificationEventFor(event, requestedSurfaces: requestedSurfaces)
    }

    private func getPropositionsFromContentCardRulesEngine(_ event: Event) -> [Surface: [Proposition]] {
        var surfacePropositions: [Surface: [Proposition]] = [:]

        if let propositionItemsBySurface = contentCardRulesEngine.evaluate(event: event) {
            for (surface, propositionItemsArray) in propositionItemsBySurface {
                var tempPropositions: [Proposition] = []
                for propositionItem in propositionItemsArray {
                    guard let propositionInfo = propositionInfo[propositionItem.itemId] else {
                        continue
                    }

                    // get proposition that this item belongs to
                    let proposition = Proposition(
                        uniqueId: propositionInfo.id,
                        scope: propositionInfo.scope,
                        scopeDetails: propositionInfo.scopeDetails,
                        items: [propositionItem]
                    )

                    // check to see if that proposition is already in the array (based on ID)
                    // if yes, append the propositionItem.  if not, create a new entry for the
                    // proposition with the new item.

                    if let existingProposition = tempPropositions.first(where: { $0.uniqueId == proposition.uniqueId }) {
                        propositionItem.proposition = existingProposition
                        existingProposition.items.append(propositionItem)
                    } else {
                        propositionItem.proposition = proposition
                        tempPropositions.append(proposition)
                    }
                }

                surfacePropositions.addArray(tempPropositions, forKey: surface)
            }
        }

        return surfacePropositions
    }

    private func dispatchNotificationEventFor(_ event: Event, requestedSurfaces: [Surface]) {
        let requestedPropositions = retrieveCachedPropositions(for: requestedSurfaces)
        guard !requestedPropositions.isEmpty else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Not dispatching a notification event, personalization:decisions response does not contain propositions.")
            return
        }

        // dispatch an event with the propositions received from the remote
        let eventData = [MessagingConstants.Event.Data.Key.PROPOSITIONS: requestedPropositions.flatMap { $0.value }].asDictionary()

        let notificationEvent = event.createChainedEvent(name: MessagingConstants.Event.Name.MESSAGE_PROPOSITIONS_NOTIFICATION,
                                                         type: EventType.messaging,
                                                         source: EventSource.notification,
                                                         data: eventData)

        dispatch(event: notificationEvent)
    }

    private func beginRequestFor(_ event: Event, with surfaces: [Surface]) {
        requestedSurfacesForEventId[event.id.uuidString] = surfaces

        // add the Edge request event to update propositions in the events queue.
        eventsQueue.add(event)
    }

    private func endRequestFor(eventId: String) {
        // update in memory propositions
        applyPropositionChangeFor(eventId: eventId)

        // remove event from surfaces dictionary
        requestedSurfacesForEventId.removeValue(forKey: eventId)

        // clear pending propositions
        inProgressPropositions.removeAll()

        // call the handler if we have one
        if let handler = completionHandlerFor(edgeRequestEventId: UUID(uuidString: eventId)) {
            handler.handle?(true)
        }
    }

    private func applyPropositionChangeFor(eventId: String) {
        // get the list of requested surfaces for this event
        guard let requestedSurfaces = requestedSurfacesForEventId[eventId] else {
            return
        }

        let parsedPropositions = ParsedPropositions(with: inProgressPropositions, requestedSurfaces: requestedSurfaces, runtime: runtime)

        // we need to preserve cache for any surfaces that were not a part of this request
        // any requested surface that is absent from the response needs to be removed from cache and persistence
        let returnedSurfaces = Array(inProgressPropositions.keys) as [Surface]
        let surfacesToRemove = requestedSurfaces.minus(returnedSurfaces)

        // update persistence, reporting data cache, and finally rules engine for in-app messages
        // order matters here because the rules engine must be a full replace, and when we update
        // persistence we will be removing empty surfaces and making sure unrequested surfaces
        // continue to have their rules active
        updatePropositions(parsedPropositions.propositionsToCache, removing: surfacesToRemove)
        updatePropositionInfo(parsedPropositions.propositionInfoToCache, removing: surfacesToRemove)
        cache.updatePropositions(parsedPropositions.propositionsToPersist, removing: surfacesToRemove)

        // apply rules
        updateRulesEngines(with: parsedPropositions.surfaceRulesBySchemaType, requestedSurfaces: requestedSurfaces)
    }

    private func updateRulesEngines(with rules: [SchemaType: [Surface: [LaunchRule]]], requestedSurfaces: [Surface]) {
        for (inboundType, newRules) in rules {
            let surfacesToRemove = requestedSurfaces.minus(Array(newRules.keys))
            switch inboundType {
            case .inapp:
                Log.trace(label: MessagingConstants.LOG_TAG, "Updating in-app message definitions for surfaces \(newRules.compactMap { $0.key.uri }).")

                // replace rules for each in-app surface we got back
                inAppRulesBySurface.merge(newRules) { _, new in new }

                // remove any surfaces that were requested but had no in-app content returned
                for surface in surfacesToRemove {
                    // calls for a dictionary extension?
                    inAppRulesBySurface.removeValue(forKey: surface)
                }

                // combine all our rules
                let allInAppRules = inAppRulesBySurface.flatMap { $0.value }

                // pre-fetch the assets for this message if there are any defined
                rulesEngine.cacheRemoteAssetsFor(allInAppRules)

                // update rules in in-app engine
                rulesEngine.launchRulesEngine.replaceRules(with: allInAppRules)

            case .feed, .contentCard:
                Log.trace(label: MessagingConstants.LOG_TAG, "Updating content card definitions for surfaces \(newRules.compactMap { $0.key.uri }).")

                // replace rules for each content card surface we got back
                contentCardRulesBySurface.merge(newRules) { _, new in new }

                // remove any surfaces that were requested but had no in-app content returned
                for surface in surfacesToRemove {
                    contentCardRulesBySurface.removeValue(forKey: surface)
                }

                // update rules in content card rules engine
                contentCardRulesEngine.launchRulesEngine.replaceRules(with: contentCardRulesBySurface.flatMap { $0.value })

                // process a generic event to see if there are any content cards with no client-side qualification
                let genericEvent = Event(name: "Seed content cards", type: EventType.messaging, source: EventSource.requestContent, data: nil)
                let qualifiedContentCardsBySurface = getPropositionsFromContentCardRulesEngine(genericEvent)
                for (surface, propositions) in qualifiedContentCardsBySurface {
                    addOrReplaceContentCards(propositions, forSurface: surface)
                }

            default:
                // no-op
                Log.trace(label: MessagingConstants.LOG_TAG, "No action will be taken updating messaging rules - the InboundType provided is not supported.")
            }
        }
    }

    /// Dispatch an event containing all propositions for the given surface
    private func retrieveMessages(for surfaces: [Surface], event: Event) {
        let requestedSurfaces = surfaces.filter { $0.isValid }

        guard !requestedSurfaces.isEmpty else {
            Log.debug(label: MessagingConstants.LOG_TAG, "Unable to retrieve propositions, no valid surface paths found.")
            dispatch(event: event.createErrorResponseEvent(AEPError.invalidRequest))
            return
        }

        // get requested content cards from cache
        let requestedContentCards = qualifiedContentCardsBySurface.filter { surfaces.contains($0.key) }

        // get requested propositions (cbe) from cache
        let requestedPropositions = retrieveCachedPropositions(for: requestedSurfaces)

        // merge the two maps
        var mergedPropositions = requestedContentCards
        for (surface, propositions) in requestedPropositions {
            mergedPropositions.addArray(propositions, forKey: surface)
        }

        let eventData = [MessagingConstants.Event.Data.Key.PROPOSITIONS: mergedPropositions.flatMap { $0.value }].asDictionary()

        let responseEvent = event.createResponseEvent(
            name: MessagingConstants.Event.Name.MESSAGE_PROPOSITIONS_RESPONSE,
            type: EventType.messaging,
            source: EventSource.responseContent,
            data: eventData
        )
        dispatch(event: responseEvent)
    }

    /// Validates that the received event contains in-app message definitions and loads them in the `MessagingRulesEngine`.
    /// - Parameter event: an `Event` containing an in-app message definition in its data
    private func handleEdgePersonalizationNotification(_ event: Event) {
        // validate this is one of our events
        guard event.isPersonalizationDecisionResponse,
              let requestEventId = event.requestEventId,
              requestedSurfacesForEventId.contains(where: { $0.key == requestEventId })
        else {
            // either this isn't the type of response we are waiting for, or it's not a response to one of our requests
            return
        }

        Log.trace(label: MessagingConstants.LOG_TAG, "Processing propositions from personalization:decisions network response for event '\(requestEventId)'.")
        updateInProgressPropositionsWith(event)
    }

    private func updateInProgressPropositionsWith(_ event: Event) {
        guard event.requestEventId != nil else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Ignoring personalization:decisions response with no requesting Event ID.")
            return
        }

        guard let eventPropositions = event.payload else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Ignoring personalization:decisions response with no propositions.")
            return
        }

        // loop through propositions for this event and add them to existing props by surface
        for proposition in eventPropositions {
            let surface = Surface(uri: proposition.scope)
            inProgressPropositions.add(proposition, forKey: surface)
        }
    }

    /// Returns propositions by surface from `cbePropositions` matching the provided `surfaces`
    private func retrieveCachedPropositions(for surfaces: [Surface]) -> [Surface: [Proposition]] {
        inMemoryPropositions.filter { surface, _ in
            surfaces.contains(where: { $0.uri == surface.uri })
        }
    }

    /// Handles Rules Consequence events containing schemas
    private func handleRulesResponse(_ event: Event) {
        guard event.isSchemaConsequence, event.data != nil else {
            Log.trace(label: MessagingConstants.LOG_TAG, "Ignoring rule consequence event. Either consequence is not of type 'schema' or 'eventData' is nil.")
            return
        }

        handleSchemaConsequence(event)
    }

    private func handleSchemaConsequence(_ event: Event) {
        guard let propositionItem = PropositionItem.fromRuleConsequenceEvent(event) else {
            return
        }

        switch propositionItem.schema {
        case .inapp:
            if
                let message = Message.fromPropositionItem(propositionItem, with: self, triggeringEvent: event),
                let propositionInfo = propositionInfoFor(messageId: propositionItem.itemId) {
                message.propositionInfo = propositionInfo
                message.trigger()
                message.show(withMessagingDelegateControl: true)
            }
        default:
            return
        }
    }

    func propositionInfoFor(messageId: String) -> PropositionInfo? {
        propositionInfo[messageId]
    }

    /// Removes and returns a `CompletionHandler` for the provided originatingEventId
    private func completionHandlerFor(originatingEventId: UUID?) -> CompletionHandler? {
        let handlerIndex = Messaging.completionHandlers.firstIndex { $0.originatingEventId == originatingEventId }
        if let index = handlerIndex {
            return Messaging.completionHandlers.remove(at: index)
        }

        return nil
    }

    /// Removes and returns a `CompletionHandler` for the provided edgeRequestEventId
    private func completionHandlerFor(edgeRequestEventId: UUID?) -> CompletionHandler? {
        let handlerIndex = Messaging.completionHandlers.firstIndex { $0.edgeRequestEventId == edgeRequestEventId }
        if let index = handlerIndex {
            return Messaging.completionHandlers.remove(at: index)
        }

        return nil
    }

    // MARK: - debug methods below are used for testing purposes only

    #if DEBUG
        func propositionInfoCount() -> Int {
            propositionInfo.count
        }

        func inMemoryPropositionsCount() -> Int {
            inMemoryPropositions.count
        }

        func setRequestedSurfacesforEventId(_ eventId: String, expectedSurfaces: [Surface]) {
            requestedSurfacesForEventId[eventId] = expectedSurfaces
        }

        func callUpdateRulesEngines(with rules: [SchemaType: [Surface: [LaunchRule]]], requestedSurfaces: [Surface]) {
            updateRulesEngines(with: rules, requestedSurfaces: requestedSurfaces)
        }
    #endif
}
