// SessionStore.swift — AgentPulse
// Manages all active AI agent sessions

import Foundation
import Combine
import AppKit
import CoreServices

class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published var sessions: [Session] = []
    @Published var activePermissions: [PermissionRequest] = []
    @Published var activeQuestions: [QuestionRequest] = []

    private let socketServer = SocketServer()
    private var cancellables = Set<AnyCancellable>()
    private var fsEventsWatcher: FSEventsWatcher?

    var activeSessions: [Session] {
        sessions.filter { $0.isActive && !$0.isHidden }
    }

    var visibleSessions: [Session] {
        sessions.filter { !$0.isHidden }
    }

    var needsAttentionCount: Int {
        sessions.filter { $0.needsAttention }.count
    }

    var hasActivePermission: Bool {
        !activePermissions.isEmpty
    }

    var hasActiveQuestion: Bool {
        !activeQuestions.isEmpty
    }

    private let persistencePath = NSHomeDirectory() + "/.agent-pulse/sessions.json"

    private init() {
        socketServer.delegate = self
        restoreSessions()

        // Auto-save on session changes (debounced)
        $sessions
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveSessions() }
            .store(in: &cancellables)
    }

    func start() {
        socketServer.start()
        startFSEventsWatcher()
    }

    func stop() {
        fsEventsWatcher?.stop()
        socketServer.stop()
    }

    // MARK: - Permission Actions

    func approvePermission(_ permission: PermissionRequest) {
        // Also approve any other pending permissions for the same session
        // (Claude Code may fire multiple hooks for parallel tool calls)
        let siblings = activePermissions.filter {
            $0.sessionId == permission.sessionId && $0.id != permission.id
        }
        sendPermissionReply(permission, allow: true, always: false)
        for sibling in siblings {
            sendPermissionReply(sibling, allow: true, always: false)
        }
    }

    func alwaysAllowPermission(_ permission: PermissionRequest) {
        let siblings = activePermissions.filter {
            $0.sessionId == permission.sessionId && $0.id != permission.id
        }
        sendPermissionReply(permission, allow: true, always: true)
        for sibling in siblings {
            sendPermissionReply(sibling, allow: true, always: true)
        }
    }

    func denyPermission(_ permission: PermissionRequest) {
        sendPermissionReply(permission, allow: false, always: false)
    }

    // MARK: - Question Actions

    // Collect answers per session for multi-question batches
    private var collectedAnswers: [String: [String]] = [:]
    // Store question texts for answer mapping
    private var answeredQuestionTexts: [String: [String]] = [:]
    // Store original questions array to echo back
    private var storedOriginalQuestions: [String: [[String: Any]]] = [:]

    func answerQuestion(_ question: QuestionRequest, answer: String) {
        guard !answer.isEmpty else { return }
        let sessionId = question.sessionId
        DiagnosticLogger.shared.log("Answering question: \(answer) session=\(sessionId)")

        // Collect this answer
        if collectedAnswers[sessionId] == nil {
            collectedAnswers[sessionId] = []
        }
        collectedAnswers[sessionId]?.append(answer)

        // Remove only THIS question
        activeQuestions.removeAll { $0.id == question.id }

        // Check remaining
        let remaining = activeQuestions.filter { $0.sessionId == sessionId }

        if remaining.isEmpty {
            // All questions answered — send via HTTP to Claude Code
            let answers = collectedAnswers.removeValue(forKey: sessionId) ?? [answer]
            sendAnswersHTTP(question: question, answers: answers)

            if let session = sessions.first(where: { $0.id == sessionId }) {
                session.pendingQuestion = nil
                session.status = .processing
            }
        }

        objectWillChange.send()
    }

    private func sendAnswersHTTP(question: QuestionRequest, answers: [String]) {
        let sessionId = question.sessionId
        let connectionId = "q-\(sessionId)"

        // Build answers dict: question text → selected answer
        // Get all questions for this session to map answers to question texts
        let sessionQuestionTexts = answeredQuestionTexts[sessionId] ?? []
        var answersDict: [String: String] = [:]
        for (index, answer) in answers.enumerated() {
            if index < sessionQuestionTexts.count {
                answersDict[sessionQuestionTexts[index]] = answer
            }
        }

        // Get original questions array to echo back
        let originalQuestions = storedOriginalQuestions[sessionId] ?? []

        let response: [String: Any] = [
            "answers": answersDict,
            "questions": originalQuestions
        ]

        DiagnosticLogger.shared.log("Sending answers via socket: \(answersDict)")
        socketServer.replyToConnection(id: connectionId, response: response)

        // Cleanup
        answeredQuestionTexts.removeValue(forKey: sessionId)
        storedOriginalQuestions.removeValue(forKey: sessionId)
    }

    func answerQuestionInTerminal(_ question: QuestionRequest) {
        removeQuestion(question)
        if let session = sessions.first(where: { $0.id == question.sessionId }) {
            session.pendingQuestion = nil
            TerminalJumper.shared.jumpToSession(session)
        }
    }

    // MARK: - Session Management

    func hideSession(_ session: Session) {
        session.isHidden = true
        objectWillChange.send()
    }

    func removeEndedSessions() {
        sessions.removeAll { $0.status == .ended }
        objectWillChange.send()
    }

    // MARK: - Private Helpers

    private func findOrCreateSession(id: String, source: String?, cwd: String?) -> Session {
        if let existing = sessions.first(where: { $0.id == id }) {
            return existing
        }
        let agentType = AgentType.from(source: source)
        let session = Session(id: id, agentType: agentType, cwd: cwd)
        sessions.append(session)
        return session
    }

    private func sendPermissionReply(_ permission: PermissionRequest, allow: Bool, always: Bool) {
        guard let port = permission.serverPort else {
            // Reply via socket
            let response: [String: Any] = ["allow": allow, "always": always]
            socketServer.replyToConnection(id: permission.id, response: response)
            removePermission(permission)
            return
        }

        // Reply via HTTP to the local agent server
        let urlStr = "http://localhost:\(port)/permission/\(permission.id)/reply"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "decision": allow ? (always ? "always_allow" : "allow") : "deny"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()

        DispatchQueue.main.async {
            self.removePermission(permission)
            if let session = self.sessions.first(where: { $0.id == permission.sessionId }) {
                session.pendingPermission = nil
                session.status = .processing
            }
        }
    }

    private func removePermission(_ permission: PermissionRequest) {
        activePermissions.removeAll { $0.id == permission.id }
        if let session = sessions.first(where: { $0.id == permission.sessionId }) {
            session.pendingPermission = nil
        }
    }

    private func removeQuestion(_ question: QuestionRequest) {
        activeQuestions.removeAll { $0.id == question.id }
        if let session = sessions.first(where: { $0.id == question.sessionId }) {
            session.pendingQuestion = nil
        }
    }

    /// Clears stale permissions/questions for a session when a new event
    /// indicates the agent moved on (user answered in terminal).
    private func clearStaleRequests(for sessionId: String) {
        let stalePerms = activePermissions.filter { $0.sessionId == sessionId }
        let staleQuestions = activeQuestions.filter { $0.sessionId == sessionId }

        if stalePerms.isEmpty && staleQuestions.isEmpty { return }

        for perm in stalePerms {
            DiagnosticLogger.shared.log("Clearing stale permission \(perm.id) for session \(sessionId)")
            activePermissions.removeAll { $0.id == perm.id }
            socketServer.closeAndRemoveConnection(id: perm.id)
        }

        if !staleQuestions.isEmpty {
            DiagnosticLogger.shared.log("Clearing \(staleQuestions.count) stale questions for session \(sessionId)")
            activeQuestions.removeAll { $0.sessionId == sessionId }
            socketServer.closeAndRemoveConnection(id: "q-\(sessionId)")
            collectedAnswers.removeValue(forKey: sessionId)
            answeredQuestionTexts.removeValue(forKey: sessionId)
            storedOriginalQuestions.removeValue(forKey: sessionId)
        }

        if let session = sessions.first(where: { $0.id == sessionId }) {
            session.pendingPermission = nil
            session.pendingQuestion = nil
        }
    }

    // MARK: - Session Persistence

    func saveSessions() {
        let snapshots = sessions.map { $0.toSnapshot() }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = .prettyPrinted
            do {
                let dir = (self.persistencePath as NSString).deletingLastPathComponent
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                let data = try encoder.encode(snapshots)
                try data.write(to: URL(fileURLWithPath: self.persistencePath), options: .atomic)
            } catch {
                DiagnosticLogger.shared.log("Failed to save sessions: \(error)")
            }
        }
    }

    private func restoreSessions() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: persistencePath),
              let data = fm.contents(atPath: persistencePath) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let snapshots = try? decoder.decode([SessionSnapshot].self, from: data) else {
            DiagnosticLogger.shared.log("Failed to decode persisted sessions")
            return
        }

        let now = Date()
        var restored: [Session] = []

        for s in snapshots {
            let age = now.timeIntervalSince(s.startTime)
            // Skip ended sessions older than 1 hour
            if s.status == .ended && age > 3600 { continue }
            // Skip active sessions older than 6 hours (abandoned)
            if s.status.isActive && age > 21600 { continue }

            let session = Session.from(snapshot: s)
            // Mark stale active sessions as ended
            if s.status.isActive && age > 1800 {
                session.status = .ended
            }
            restored.append(session)
        }

        if !restored.isEmpty {
            sessions = restored
            DiagnosticLogger.shared.log("Restored \(restored.count) sessions from disk")
        }
    }

    // MARK: - FSEvents Session Discovery

    private func startFSEventsWatcher() {
        let claudeProjectsDir = NSHomeDirectory() + "/.claude/projects"
        guard FileManager.default.fileExists(atPath: claudeProjectsDir) else {
            DiagnosticLogger.shared.log("No ~/.claude/projects/ directory, skipping FSEvents")
            return
        }

        fsEventsWatcher = FSEventsWatcher(paths: [claudeProjectsDir])
        fsEventsWatcher?.onNewSession = { [weak self] path in
            self?.handleDiscoveredPath(path)
        }
        fsEventsWatcher?.start()
    }

    private func handleDiscoveredPath(_ path: String) {
        guard path.hasSuffix(".jsonl") else { return }

        let sessionFile = (path as NSString).lastPathComponent
        let sessionId = sessionFile.replacingOccurrences(of: ".jsonl", with: "")

        // Don't create if we already know this session
        if sessions.contains(where: { $0.id == sessionId }) { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var cwd: String?
            if let handle = FileHandle(forReadingAtPath: path) {
                let data = handle.readData(ofLength: 4096)
                handle.closeFile()
                if let firstLine = String(data: data, encoding: .utf8)?.split(separator: "\n").first,
                   let json = try? JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any] {
                    cwd = json["cwd"] as? String
                }
            }

            DispatchQueue.main.async {
                guard let self, !self.sessions.contains(where: { $0.id == sessionId }) else { return }
                let session = Session(id: sessionId, agentType: .claude, cwd: cwd)
                session.status = .processing
                self.sessions.append(session)
                self.objectWillChange.send()
                DiagnosticLogger.shared.log("FSEvents discovered session: \(sessionId)")
            }
        }
    }

}

// MARK: - FSEventsWatcher

private class FSEventsWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    var onNewSession: ((String) -> Void)?

    init(paths: [String]) {
        self.paths = paths
    }

    func start() {
        let pathsCF = paths as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            pathsCF,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        DiagnosticLogger.shared.log("FSEvents watcher started for \(paths)")
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

private func fsEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
    for path in paths {
        watcher.onNewSession?(path)
    }
}

// MARK: - SocketServerDelegate

extension SessionStore: SocketServerDelegate {
    func socketServer(_ server: SocketServer, didReceiveEvent event: [String: Any], connection: SocketConnection) {
        let sessionId = event["session_id"] as? String ?? UUID().uuidString
        let eventName = event["hook_event_name"] as? String ?? ""
        let source = event["_source"] as? String
        let cwd = event["cwd"] as? String
        let toolName = event["tool_name"] as? String
        DiagnosticLogger.shared.log("\(eventName) session=\(sessionId) tool=\(toolName ?? "-")")
        let status = event["status"] as? String
        let prompt = event["prompt"] as? String
        let message = event["last_assistant_message"] as? String
        let serverPort = event["_server_port"] as? Int
        let title = event["title"] as? String
        let model = event["model"] as? String

        let session = findOrCreateSession(id: sessionId, source: source, cwd: cwd)

        if let cwd = cwd { session.cwd = cwd }
        if let title = title { session.title = title }
        if let model = model { session.model = model }
        if let port = serverPort { session.serverPort = port }
        if let prompt = prompt { session.lastPrompt = prompt }
        if let message = message { session.lastAssistantMessage = message }

        // Terminal identification
        if let bundleId = event["_env___CFBundleIdentifier"] as? String, session.terminalBundleId == nil {
            session.terminalBundleId = bundleId
        }
        if let termSessionId = event["_env_ITERM_SESSION_ID"] as? String
            ?? event["_env_TERM_SESSION_ID"] as? String {
            session.terminalSessionId = termSessionId
        }
        if let kittyId = event["_env_KITTY_WINDOW_ID"] as? String {
            session.kittyWindowId = kittyId
        }
        if let tmuxPane = event["_env_TMUX_PANE"] as? String {
            session.tmuxPane = tmuxPane
        }

        // Rate limits
        if let rl = event["rate_limits"] as? [String: Any] {
            session.rateLimits = RateLimits.from(rl)
        }

        // Parent/child tracking
        if let parentId = event["parent_thread_id"] as? String {
            session.parentSessionId = parentId
            if let parent = sessions.first(where: { $0.id == parentId }),
               !parent.childAgentIds.contains(sessionId) {
                parent.childAgentIds.append(sessionId)
            }
        }

        // If an event arrives that indicates the agent moved past a pending
        // question/permission, the user must have answered in terminal.
        // Only clear on events that genuinely mean "agent progressed":
        let progressEvents: Set<String> = [
            "PreToolUse", "PostToolUse", "PostToolUseFailure",
            "UserPromptSubmit", "Stop", "SessionEnd", "StopFailure", "SubagentStop"
        ]
        if progressEvents.contains(eventName) {
            // PreToolUse for AskUserQuestion IS the question itself — don't clear
            let isAskUserQuestion = eventName == "PreToolUse" && toolName == "AskUserQuestion"
            if !isAskUserQuestion {
                clearStaleRequests(for: sessionId)
            }
        }

        switch eventName {
        case "SessionStart":
            session.status = .processing
            SoundManager.shared.play(.sessionStart)
            addEvent(to: session, type: "session_start", tool: nil, detail: cwd)

        case "Stop":
            // Agent finished its turn, waiting for user input
            session.status = .waitingForInput
            session.currentTool = nil
            SoundManager.shared.play(.inputRequired)
            addEvent(to: session, type: "waiting_input", tool: nil, detail: message)

        case "SessionEnd", "StopFailure", "SubagentStop":
            session.status = .ended
            SoundManager.shared.play(.sessionEnd)
            addEvent(to: session, type: "session_end", tool: nil, detail: nil)

        case "UserPromptSubmit":
            session.status = .processing
            addEvent(to: session, type: "prompt", tool: nil, detail: prompt)

        case "PermissionRequest":
            let toolInput = event["tool_input"] as? [String: Any] ?? [:]
            let requestId = event["_opencode_request_id"] as? String ?? UUID().uuidString

            if toolName == "AskUserQuestion" {
                let rawQuestions = toolInput["questions"] as? [[String: Any]] ?? []

                // Store original questions for response echo
                storedOriginalQuestions[sessionId] = rawQuestions

                // Hold socket connection — bridge is waiting for our reply
                let connectionId = "q-\(sessionId)"
                socketServer.holdConnection(id: connectionId, connection: connection)
                DiagnosticLogger.shared.log("AskUserQuestion via PermissionRequest, holding connection \(connectionId)")

                var questionTexts: [String] = []

                for (index, qObj) in rawQuestions.enumerated() {
                    let qText = qObj["question"] as? String ?? "Question"
                    let header = qObj["header"] as? String
                    let isMultiSelect = qObj["multiSelect"] as? Bool ?? false
                    questionTexts.append(qText)

                    // Parse options with descriptions
                    var optLabels: [String]? = nil
                    var optDescs: [String]? = nil
                    if let optObjects = qObj["options"] as? [[String: Any]] {
                        optLabels = optObjects.map { $0["label"] as? String ?? "" }
                        optDescs = optObjects.map { $0["description"] as? String ?? "" }
                    } else if let optStrings = qObj["options"] as? [String] {
                        optLabels = optStrings
                    }

                    let qId = "\(sessionId)-q\(index)"
                    let q = QuestionRequest(
                        id: qId,
                        sessionId: sessionId,
                        question: qText,
                        header: header,
                        options: optLabels,
                        optionDescriptions: optDescs,
                        multiSelect: isMultiSelect,
                        serverPort: serverPort,
                        toolUseId: event["tool_use_id"] as? String
                    )
                    session.pendingQuestion = q
                    session.status = .question
                    activeQuestions.append(q)
                }

                if questionTexts.isEmpty {
                    questionTexts = ["Agent has a question"]
                    let q = QuestionRequest(id: "\(sessionId)-q0", sessionId: sessionId, question: "Agent has a question")
                    activeQuestions.append(q)
                }
                answeredQuestionTexts[sessionId] = questionTexts
                SoundManager.shared.play(.question)
            } else {
                let perm = PermissionRequest(
                    id: requestId,
                    sessionId: sessionId,
                    toolName: toolName ?? "Unknown",
                    toolInput: toolInput,
                    serverPort: serverPort
                )
                session.pendingPermission = perm
                session.status = .waitingForApproval
                activePermissions.append(perm)
                SoundManager.shared.play(.permissionRequest)

                // Hold connection for socket-based reply
                socketServer.holdConnection(id: requestId, connection: connection)
            }
            addEvent(to: session, type: "permission_request", tool: toolName, detail: nil)

        case "PreToolUse":
            // Skip AskUserQuestion here — handled via PermissionRequest hook
            if toolName != "AskUserQuestion" {
                session.status = .runningTool
                session.currentTool = toolName
                addEvent(to: session, type: "tool_start", tool: toolName, detail: nil)
            }

        case "PostToolUse", "PostToolUseFailure":
            session.currentTool = nil
            session.status = .processing
            addEvent(to: session, type: "tool_use", tool: toolName, detail: nil)

        case "Notification":
            let notifType = event["notification_type"] as? String
            let notifMessage = event["message"] as? String
            if notifType == "compacting" {
                session.status = .compacting
            } else if notifType == "permission_prompt" {
                // Claude needs attention — keep session active, play sound
                session.status = .waitingForInput
                SoundManager.shared.play(.inputRequired)
            }
            addEvent(to: session, type: "notification", tool: nil, detail: notifMessage)

        default:
            // Handle status updates
            if let status = status {
                session.status = SessionStatus(rawValue: status) ?? .unknown
            }
        }

        // Update status from explicit status field
        if let status = status, eventName != "PermissionRequest" {
            let s = SessionStatus(rawValue: status) ?? .unknown
            if s != .unknown { session.status = s }
        }

        objectWillChange.send()
    }

    private func addEvent(to session: Session, type: String, tool: String?, detail: String?) {
        let event = SessionEvent(
            timestamp: Date(),
            eventType: type,
            toolName: tool,
            detail: detail
        )
        session.events.append(event)
        if session.events.count > 50 {
            session.events.removeFirst(session.events.count - 50)
        }
    }
}
