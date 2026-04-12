// Models.swift — AgentPulse
// All core data types

import Foundation
import AppKit
import Combine
import Carbon

// MARK: - Agent Type

enum AgentType: String, CaseIterable, Identifiable, Codable {
    case claude = "claude"
    case codex = "codex"
    case gemini = "gemini"
    case opencode = "opencode"
    case droid = "droid"
    case qoder = "qoder"
    case cursor = "cursor"
    case unknown = "unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:   return "Claude Code"
        case .codex:    return "Codex"
        case .gemini:   return "Gemini CLI"
        case .opencode: return "OpenCode"
        case .droid:    return "Droid"
        case .qoder:    return "Qoder"
        case .cursor:   return "Cursor"
        case .unknown:  return "Agent"
        }
    }

    var iconName: String {
        switch self {
        case .claude:   return "brain.head.profile"
        case .codex:    return "terminal"
        case .gemini:   return "sparkles"
        case .opencode: return "chevron.left.forwardslash.chevron.right"
        case .droid:    return "cpu"
        case .qoder:    return "qrcode"
        case .cursor:   return "cursorarrow.rays"
        case .unknown:  return "questionmark.circle"
        }
    }

    var color: NSColor {
        switch self {
        case .claude:   return NSColor(red: 0.85, green: 0.55, blue: 0.35, alpha: 1)
        case .codex:    return NSColor(red: 0.3, green: 0.8, blue: 0.5, alpha: 1)
        case .gemini:   return NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        case .opencode: return NSColor(red: 0.7, green: 0.4, blue: 0.9, alpha: 1)
        case .droid:    return NSColor(red: 0.2, green: 0.8, blue: 0.8, alpha: 1)
        case .qoder:    return NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1)
        case .cursor:   return NSColor(red: 0.0, green: 0.7, blue: 0.9, alpha: 1)
        case .unknown:  return NSColor.gray
        }
    }

    static func from(source: String?) -> AgentType {
        guard let s = source?.lowercased() else { return .unknown }
        return AgentType(rawValue: s) ?? .unknown
    }
}

// MARK: - Session Status

enum SessionStatus: String, Codable {
    case waitingForInput   = "waiting_for_input"
    case processing        = "processing"
    case thinking          = "thinking"
    case runningTool       = "running_tool"
    case waitingForApproval = "waiting_for_approval"
    case question          = "question"
    case compacting        = "compacting"
    case ended             = "ended"
    case notification      = "notification"
    case unknown           = "unknown"

    var displayName: String {
        switch self {
        case .waitingForInput:    return "Waiting for input"
        case .processing:         return "Processing"
        case .thinking:           return "Thinking"
        case .runningTool:        return "Running tool"
        case .waitingForApproval: return "Needs approval"
        case .question:           return "Waiting for answer"
        case .compacting:         return "Compacting"
        case .ended:              return "Ended"
        case .notification:       return "Notification"
        case .unknown:            return "Unknown"
        }
    }

    var isActive: Bool {
        switch self {
        case .ended, .unknown: return false
        default: return true
        }
    }

    var needsAttention: Bool {
        switch self {
        case .waitingForApproval, .question, .waitingForInput: return true
        default: return false
        }
    }

    var statusColor: NSColor {
        switch self {
        case .processing, .runningTool, .thinking:
            return NSColor.systemGreen
        case .waitingForApproval:
            return NSColor.systemOrange
        case .question, .waitingForInput:
            return NSColor.systemPurple
        case .compacting:
            return NSColor.systemYellow
        case .ended:
            return NSColor.systemGray
        case .notification:
            return NSColor.systemBlue
        case .unknown:
            return NSColor.systemGray
        }
    }
}

// MARK: - Session Event

struct SessionEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let eventType: String
    let toolName: String?
    let detail: String?
}

// MARK: - Permission Request

class PermissionRequest: ObservableObject, Identifiable {
    let id: String
    let sessionId: String
    let toolName: String
    let toolInput: [String: Any]
    let serverPort: Int?
    let timestamp = Date()

    init(id: String = UUID().uuidString, sessionId: String, toolName: String,
         toolInput: [String: Any] = [:], serverPort: Int? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.toolName = toolName
        self.toolInput = toolInput
        self.serverPort = serverPort
    }

    var displayCommand: String? {
        if toolName == "Bash" || toolName == "run_in_terminal" {
            return toolInput["command"] as? String
        }
        return nil
    }

    var displayFilePath: String? {
        if let fp = toolInput["file_path"] as? String { return fp }
        if let fp = toolInput["path"] as? String { return fp }
        return nil
    }

    var displayDescription: String {
        switch toolName {
        case "Bash", "run_in_terminal":
            return displayCommand ?? "Run command"
        case "Edit", "search_replace":
            return "Edit \(shortPath(displayFilePath))"
        case "Write", "create_file":
            return "Write \(shortPath(displayFilePath))"
        case "Read", "read_file":
            return "Read \(shortPath(displayFilePath))"
        case "Grep", "grep_code":
            return "Search code"
        case "Glob", "search_file", "list_dir":
            return "Find files"
        case "WebFetch", "fetch_content":
            return "Fetch URL"
        case "WebSearch", "search_web":
            return "Web search"
        default:
            return "Allow \(toolName)"
        }
    }

    private func shortPath(_ path: String?) -> String {
        guard let p = path else { return "file" }
        let components = p.split(separator: "/")
        if components.count <= 2 { return p }
        return ".../" + components.suffix(2).joined(separator: "/")
    }
}

// MARK: - Question Request

class QuestionRequest: ObservableObject, Identifiable {
    let id: String
    let sessionId: String
    let question: String
    let header: String?
    let options: [String]?
    let optionDescriptions: [String]?
    let multiSelect: Bool
    let serverPort: Int?
    let toolUseId: String?
    let timestamp = Date()
    @Published var answer: String = ""

    init(id: String = UUID().uuidString, sessionId: String, question: String,
         header: String? = nil, options: [String]? = nil, optionDescriptions: [String]? = nil,
         multiSelect: Bool = false, serverPort: Int? = nil, toolUseId: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.question = question
        self.header = header
        self.options = options
        self.optionDescriptions = optionDescriptions
        self.multiSelect = multiSelect
        self.serverPort = serverPort
        self.toolUseId = toolUseId
    }
}

// MARK: - Rate Limits

struct RateLimits {
    var primaryUsedPercent: Double
    var primaryResetsAt: String?
    var secondaryUsedPercent: Double?
    var secondaryResetsAt: String?

    static func from(_ dict: [String: Any]) -> RateLimits? {
        guard let primary = dict["primary_used_percent"] as? Double else { return nil }
        return RateLimits(
            primaryUsedPercent: primary,
            primaryResetsAt: dict["primary_resets_at"] as? String,
            secondaryUsedPercent: dict["secondary_used_percent"] as? Double,
            secondaryResetsAt: dict["secondary_resets_at"] as? String
        )
    }
}

// MARK: - Task Item

struct TaskItem: Identifiable {
    let id = UUID()
    let title: String
    var status: TaskStatus

    enum TaskStatus: String {
        case pending, inProgress = "in_progress", completed
    }
}

// MARK: - Session

class Session: ObservableObject, Identifiable {
    let id: String
    let agentType: AgentType
    let startTime: Date

    @Published var status: SessionStatus = .processing
    @Published var currentTool: String?
    @Published var lastPrompt: String?
    @Published var lastAssistantMessage: String?
    @Published var title: String?
    @Published var cwd: String?
    @Published var pendingPermission: PermissionRequest?
    @Published var pendingQuestion: QuestionRequest?
    @Published var events: [SessionEvent] = []
    @Published var childAgentIds: [String] = []
    @Published var rateLimits: RateLimits?
    @Published var model: String?
    @Published var tasks: [TaskItem] = []
    @Published var isHidden: Bool = false

    var serverPort: Int?
    var parentSessionId: String?
    var terminalBundleId: String?
    var terminalSessionId: String?
    var tmuxPane: String?
    var kittyWindowId: String?

    init(id: String, agentType: AgentType, cwd: String? = nil, startTime: Date = Date()) {
        self.id = id
        self.agentType = agentType
        self.startTime = startTime
        self.cwd = cwd
    }

    var projectName: String {
        guard let cwd = cwd else { return "session" }
        return cwd.split(separator: "/").last.map(String.init) ?? "session"
    }

    var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    var durationString: String {
        let d = duration
        if d < 60 { return "\(Int(d))s" }
        if d < 3600 { return "\(Int(d / 60))m" }
        return "\(Int(d / 3600))h \(Int(d.truncatingRemainder(dividingBy: 3600) / 60))m"
    }

    var toolCount: Int {
        events.filter { $0.eventType == "tool_use" }.count
    }

    var isActive: Bool { status.isActive }
    var needsAttention: Bool { status.needsAttention }
}

// MARK: - Layout Mode

enum LayoutMode: String {
    case clean = "clean"
    case detailed = "detailed"
}

// MARK: - Session Snapshot (Persistence)

struct SessionSnapshot: Codable {
    let id: String
    let agentType: AgentType
    let startTime: Date
    let status: SessionStatus
    let cwd: String?
    let title: String?
    let model: String?
    let terminalBundleId: String?
    let terminalSessionId: String?
    let tmuxPane: String?
    let kittyWindowId: String?
    let toolCount: Int
    let isHidden: Bool
    let parentSessionId: String?
    let childAgentIds: [String]
}

extension Session {
    func toSnapshot() -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            agentType: agentType,
            startTime: startTime,
            status: status,
            cwd: cwd,
            title: title,
            model: model,
            terminalBundleId: terminalBundleId,
            terminalSessionId: terminalSessionId,
            tmuxPane: tmuxPane,
            kittyWindowId: kittyWindowId,
            toolCount: toolCount,
            isHidden: isHidden,
            parentSessionId: parentSessionId,
            childAgentIds: childAgentIds
        )
    }

    static func from(snapshot s: SessionSnapshot) -> Session {
        let session = Session(id: s.id, agentType: s.agentType, cwd: s.cwd, startTime: s.startTime)
        session.status = s.status
        session.title = s.title
        session.model = s.model
        session.terminalBundleId = s.terminalBundleId
        session.terminalSessionId = s.terminalSessionId
        session.tmuxPane = s.tmuxPane
        session.kittyWindowId = s.kittyWindowId
        session.isHidden = s.isHidden
        session.parentSessionId = s.parentSessionId
        session.childAgentIds = s.childAgentIds
        return session
    }
}

// MARK: - Modifier Key Option

enum ModifierKeyOption: String, CaseIterable {
    case control = "control"
    case option = "option"
    case command = "command"

    var displayName: String {
        switch self {
        case .control: return "⌃ Control"
        case .option:  return "⌥ Option"
        case .command: return "⌘ Command"
        }
    }

    var carbonModifier: UInt32 {
        switch self {
        case .control: return UInt32(controlKey)
        case .option:  return UInt32(optionKey)
        case .command: return UInt32(cmdKey)
        }
    }

    var nsEventModifier: NSEvent.ModifierFlags {
        switch self {
        case .control: return .control
        case .option:  return .option
        case .command: return .command
        }
    }
}
