// SessionStore.swift — AgentPulse
// Manages all active AI agent sessions

import Foundation
import Combine
import AppKit

class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published var sessions: [Session] = []
    @Published var activePermissions: [PermissionRequest] = []
    @Published var activeQuestions: [QuestionRequest] = []

    private let socketServer = SocketServer()
    private var cancellables = Set<AnyCancellable>()

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

    private init() {
        socketServer.delegate = self
    }

    func start() {
        socketServer.start()
    }

    func stop() {
        socketServer.stop()
    }

    // MARK: - Permission Actions

    func approvePermission(_ permission: PermissionRequest) {
        sendPermissionReply(permission, allow: true, always: false)
    }

    func alwaysAllowPermission(_ permission: PermissionRequest) {
        sendPermissionReply(permission, allow: true, always: true)
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

        switch eventName {
        case "SessionStart":
            session.status = .processing
            SoundManager.shared.play(.sessionStart)
            addEvent(to: session, type: "session_start", tool: nil, detail: cwd)

        case "Stop":
            // Agent finished its turn, waiting for user input
            session.status = .waitingForInput
            session.currentTool = nil
            session.pendingPermission = nil
            session.pendingQuestion = nil
            SoundManager.shared.play(.inputRequired)
            addEvent(to: session, type: "waiting_input", tool: nil, detail: message)

        case "SessionEnd", "StopFailure", "SubagentStop":
            session.status = .ended
            session.pendingPermission = nil
            session.pendingQuestion = nil
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
