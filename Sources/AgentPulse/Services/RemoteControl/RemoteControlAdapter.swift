// RemoteControlAdapter.swift — AgentPulse
// Protocol for remote control channels (Telegram, Discord, web dashboard, etc.)
//
// Adapters receive RemoteControlEvents from RemoteControlService and push
// RemoteControlResponses back via the onResponse closure. They must NEVER
// touch SessionStore or the socket layer directly — all routing goes
// through RemoteControlService → SessionStore's canonical methods.

import Foundation

/// Events pushed from RemoteControlService to all enabled adapters.
enum RemoteControlEvent {
    case permissionRequested(PermissionRequest, sessionTitle: String, agentType: AgentType)
    case questionRequested(QuestionRequest, sessionTitle: String, agentType: AgentType)
    /// A permission request disappeared from SessionStore (handled via any channel,
    /// timed out, or session ended). Adapters should dismiss their UI for it.
    case permissionResolved(requestId: String)
    case questionResolved(requestId: String)
    case sessionStarted(Session)
    case sessionEnded(Session)
}

/// Responses pushed from adapters back to RemoteControlService.
/// These are translated into calls on SessionStore's public API.
enum RemoteControlResponse {
    case approvePermission(requestId: String)
    case alwaysAllowPermission(requestId: String)
    case denyPermission(requestId: String)
    case answerQuestion(requestId: String, answer: String)
}

protocol RemoteControlAdapter: AnyObject {
    /// Stable identifier, e.g. "telegram", "discord". Used for reloadAdapter routing.
    var identifier: String { get }

    /// Driven by user settings. Service only starts and broadcasts to enabled adapters.
    var isEnabled: Bool { get }

    /// Called once on app launch if enabled, and again via reloadAdapter after settings change.
    func start() async

    /// Called on app terminate or when the adapter is disabled via settings.
    func stop() async

    /// Fired for every RemoteControlEvent the service observes.
    func notify(_ event: RemoteControlEvent) async

    /// Set by RemoteControlService at registration time. Adapters call this
    /// from their receive path whenever the user acts in the channel.
    /// The closure is safe to call from any thread — the service hops to main.
    var onResponse: ((RemoteControlResponse) -> Void)? { get set }
}
