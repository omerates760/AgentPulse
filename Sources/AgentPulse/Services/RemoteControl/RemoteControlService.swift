// RemoteControlService.swift — AgentPulse
// Central service that observes SessionStore and fans out permission/question
// events to registered RemoteControlAdapter instances (Telegram, future web
// dashboard, etc.). Adapter responses are routed back through SessionStore's
// canonical approve/deny/always/answerQuestion methods — never through a
// parallel code path.
//
// Threading: all SessionStore access stays on the main thread (matching the
// rest of the app's ObservableObject pattern). Combine sinks use
// .receive(on: DispatchQueue.main). Adapter onResponse closures may fire on
// any thread; handleResponse is always hopped onto main via DispatchQueue.

import Foundation
import Combine

final class RemoteControlService {
    static let shared = RemoteControlService()

    private var adapters: [RemoteControlAdapter] = []
    private var cancellables = Set<AnyCancellable>()
    private var knownPermissionIds = Set<String>()
    private var knownQuestionIds = Set<String>()

    private var sessionStore: SessionStore { SessionStore.shared }

    private init() {}

    // MARK: - Lifecycle

    func start() {
        registerBuiltInAdapters()
        subscribeToSessionStore()
        // Seed the known-id sets with whatever is already active so we don't
        // emit stale "new" events for requests that predate us.
        knownPermissionIds = Set(sessionStore.activePermissions.map(\.id))
        knownQuestionIds = Set(sessionStore.activeQuestions.map(\.id))
        Task { [adapters] in
            for adapter in adapters where adapter.isEnabled {
                await adapter.start()
            }
        }
        DiagnosticLogger.shared.log("RemoteControlService started (\(adapters.count) adapters)")
    }

    func stop() {
        cancellables.removeAll()
        let snapshot = adapters
        Task {
            for adapter in snapshot { await adapter.stop() }
        }
        DiagnosticLogger.shared.log("RemoteControlService stopped")
    }

    /// Called by Settings UI after the user toggles enable or saves new credentials.
    func reloadAdapter(identifier: String) {
        guard let adapter = adapters.first(where: { $0.identifier == identifier }) else {
            DiagnosticLogger.shared.log("RemoteControl: reload requested for unknown adapter \(identifier)")
            return
        }
        Task {
            await adapter.stop()
            if adapter.isEnabled { await adapter.start() }
        }
    }

    /// Typed accessor for the Telegram adapter so the Settings UI can invoke
    /// testConnection / discoverChatId without going through the generic
    /// adapter protocol.
    var telegramAdapter: TelegramAdapter? {
        adapters.compactMap { $0 as? TelegramAdapter }.first
    }

    // MARK: - Adapter registration

    private func registerBuiltInAdapters() {
        guard adapters.isEmpty else { return }

        // NoOpAdapter logs every broadcast to DiagnosticLogger for debugging.
        // Always enabled; safe to leave in place.
        let noop = NoOpRemoteControlAdapter()
        noop.onResponse = { [weak self] response in
            DispatchQueue.main.async { self?.handleResponse(response) }
        }
        adapters.append(noop)

        // Telegram adapter — dormant until the user configures a token and
        // pairs a chat via Settings. Its isEnabled gate prevents broadcasts
        // until then.
        let telegram = TelegramAdapter()
        telegram.onResponse = { [weak self] response in
            DispatchQueue.main.async { self?.handleResponse(response) }
        }
        adapters.append(telegram)
    }

    // MARK: - SessionStore subscription

    private func subscribeToSessionStore() {
        sessionStore.$activePermissions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] perms in
                self?.reconcilePermissions(perms)
            }
            .store(in: &cancellables)

        sessionStore.$activeQuestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] qs in
                self?.reconcileQuestions(qs)
            }
            .store(in: &cancellables)
    }

    private func reconcilePermissions(_ current: [PermissionRequest]) {
        let currentIds = Set(current.map(\.id))
        // Newly appeared. Smart suppression skips the outbound notification when
        // a terminal/IDE is in focus — the user is already engaged. Resolved
        // events still fire below so adapters can clean up any UI they posted.
        for perm in current where !knownPermissionIds.contains(perm.id) {
            if SmartSuppression.shouldSuppress() {
                DiagnosticLogger.shared.log("RemoteControl: suppressed permission broadcast id=\(perm.id) (terminal focused)")
                continue
            }
            let (title, agent) = sessionMeta(for: perm.sessionId)
            broadcast(.permissionRequested(perm, sessionTitle: title, agentType: agent))
        }
        // Resolved (disappeared)
        for oldId in knownPermissionIds.subtracting(currentIds) {
            broadcast(.permissionResolved(requestId: oldId))
        }
        knownPermissionIds = currentIds
    }

    private func reconcileQuestions(_ current: [QuestionRequest]) {
        let currentIds = Set(current.map(\.id))
        for q in current where !knownQuestionIds.contains(q.id) {
            if SmartSuppression.shouldSuppress() {
                DiagnosticLogger.shared.log("RemoteControl: suppressed question broadcast id=\(q.id) (terminal focused)")
                continue
            }
            let (title, agent) = sessionMeta(for: q.sessionId)
            broadcast(.questionRequested(q, sessionTitle: title, agentType: agent))
        }
        for oldId in knownQuestionIds.subtracting(currentIds) {
            broadcast(.questionResolved(requestId: oldId))
        }
        knownQuestionIds = currentIds
    }

    private func sessionMeta(for sessionId: String) -> (title: String, agent: AgentType) {
        if let s = sessionStore.sessions.first(where: { $0.id == sessionId }) {
            return (s.title ?? s.projectName, s.agentType)
        }
        return ("session", .unknown)
    }

    private func broadcast(_ event: RemoteControlEvent) {
        for adapter in adapters where adapter.isEnabled {
            Task { await adapter.notify(event) }
        }
    }

    // MARK: - Response routing (adapter → SessionStore)

    fileprivate func handleResponse(_ response: RemoteControlResponse) {
        switch response {
        case .approvePermission(let id):
            guard let perm = sessionStore.activePermissions.first(where: { $0.id == id }) else {
                logStale(id); return
            }
            sessionStore.approvePermission(perm)

        case .alwaysAllowPermission(let id):
            guard let perm = sessionStore.activePermissions.first(where: { $0.id == id }) else {
                logStale(id); return
            }
            sessionStore.alwaysAllowPermission(perm)

        case .denyPermission(let id):
            guard let perm = sessionStore.activePermissions.first(where: { $0.id == id }) else {
                logStale(id); return
            }
            sessionStore.denyPermission(perm)

        case .answerQuestion(let id, let answer):
            guard let q = sessionStore.activeQuestions.first(where: { $0.id == id }) else {
                logStale(id); return
            }
            sessionStore.answerQuestion(q, answer: answer)
        }
    }

    private func logStale(_ id: String) {
        DiagnosticLogger.shared.log("RemoteControl: stale response for request=\(id) (already resolved)")
    }
}

// MARK: - NoOpAdapter (Step 1 wiring verification)

/// Logs every broadcast event to DiagnosticLogger. Useful for verifying the
/// RemoteControlService → adapter fan-out works end-to-end before a real
/// adapter (Telegram) is wired up. Safe to leave in place as a debug helper.
private final class NoOpRemoteControlAdapter: RemoteControlAdapter {
    let identifier = "noop"
    var isEnabled: Bool { true }
    var onResponse: ((RemoteControlResponse) -> Void)?

    func start() async {
        DiagnosticLogger.shared.log("[rc/noop] started")
    }

    func stop() async {
        DiagnosticLogger.shared.log("[rc/noop] stopped")
    }

    func notify(_ event: RemoteControlEvent) async {
        switch event {
        case .permissionRequested(let perm, let title, let agent):
            DiagnosticLogger.shared.log(
                "[rc/noop] permissionRequested id=\(perm.id) tool=\(perm.toolName) agent=\(agent.displayName) session=\(title)"
            )
        case .questionRequested(let q, let title, let agent):
            DiagnosticLogger.shared.log(
                "[rc/noop] questionRequested id=\(q.id) multi=\(q.multiSelect) agent=\(agent.displayName) session=\(title)"
            )
        case .permissionResolved(let id):
            DiagnosticLogger.shared.log("[rc/noop] permissionResolved id=\(id)")
        case .questionResolved(let id):
            DiagnosticLogger.shared.log("[rc/noop] questionResolved id=\(id)")
        case .sessionStarted(let s):
            DiagnosticLogger.shared.log("[rc/noop] sessionStarted id=\(s.id) agent=\(s.agentType.displayName)")
        case .sessionEnded(let s):
            DiagnosticLogger.shared.log("[rc/noop] sessionEnded id=\(s.id)")
        }
    }
}
