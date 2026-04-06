// main.swift — AgentPulse Bridge
// Hook binary that receives events from AI tools and forwards to AgentPulse via Unix socket

import Foundation

// MARK: - Configuration

let socketPath = "/tmp/agent-pulse.sock"
let logPath = "/tmp/agent-pulse-bridge.log"

// MARK: - Logging

func bridgeLog(_ msg: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8) ?? Data())
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8))
    }
}

// MARK: - Environment Collection

func collectEnvironment() -> [String: String] {
    let keys = [
        "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
        "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID",
        "__CFBundleIdentifier", "CURSOR_TRACE_ID",
        "CONDUCTOR_WORKSPACE_NAME", "CONDUCTOR_PORT",
        "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH",
    ]
    var env: [String: String] = [:]
    for key in keys {
        if let val = ProcessInfo.processInfo.environment[key] {
            env[key] = val
        }
    }
    return env
}

// MARK: - Socket Communication

func sendToSocket(_ payload: [String: Any]) -> Data? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        bridgeLog("socket create failed: \(errno)")
        return nil
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = socketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        let raw = UnsafeMutableRawPointer(ptr)
        pathBytes.withUnsafeBufferPointer { buf in
            raw.copyMemory(from: buf.baseAddress!, byteCount: min(buf.count, 104))
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        bridgeLog("socket connect failed: \(errno)")
        return nil
    }

    // Send JSON payload
    guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
        bridgeLog("JSON serialization failed")
        return nil
    }

    var sendData = jsonData
    sendData.append(contentsOf: [0x0A]) // newline delimiter
    _ = sendData.withUnsafeBytes { bytes in
        Darwin.send(fd, bytes.baseAddress!, bytes.count, 0)
    }

    // PermissionRequest waits for response (includes AskUserQuestion)
    let hookEvent = payload["hook_event_name"] as? String ?? ""
    let needsResponse = hookEvent == "PermissionRequest"
    if needsResponse {
        let toolName = payload["tool_name"] as? String ?? ""
        let timeout: Int = toolName == "AskUserQuestion" ? 300 : 30
        bridgeLog("waiting for response session=\(payload["session_id"] ?? "?") tool=\(toolName) timeout=\(timeout)s")

        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Read response (line-delimited)
        var buffer = Data()
        var byte = [UInt8](repeating: 0, count: 1)
        while true {
            let n = recv(fd, &byte, 1, 0)
            if n <= 0 { break }
            if byte[0] == 0x0A { break }
            buffer.append(byte[0])
        }

        if !buffer.isEmpty {
            bridgeLog("permission response received \(buffer.count) bytes")
            return buffer
        }
        bridgeLog("permission timeout/no-response session=\(payload["session_id"] ?? "?")")
    }

    return nil
}

// MARK: - Event Mapping

func mapToolName(_ tool: String) -> String {
    // Map between different tool naming conventions
    switch tool {
    case "run_in_terminal": return "Bash"
    case "create_file": return "Write"
    case "search_replace": return "Edit"
    case "read_file": return "Read"
    case "grep_code": return "Grep"
    case "search_file", "list_dir": return "Glob"
    case "search_web": return "WebSearch"
    case "fetch_content": return "WebFetch"
    default: return tool
    }
}

// MARK: - Main

func main() {
    // Skip if explicitly disabled
    if ProcessInfo.processInfo.environment["VIBE_ISLAND_SKIP"] != nil {
        exit(0)
    }

    // Parse arguments
    let args = CommandLine.arguments
    var source = "claude"

    var i = 1
    while i < args.count {
        if args[i] == "--source" && i + 1 < args.count {
            source = args[i + 1]
            i += 2
        } else {
            i += 1
        }
    }

    // Read stdin (hook payload from AI tool)
    let stdinData = FileHandle.standardInput.readDataToEndOfFile()

    guard !stdinData.isEmpty else {
        bridgeLog("no stdin or invalid JSON")
        exit(0)
    }

    guard let inputJSON = try? JSONSerialization.jsonObject(with: stdinData) as? [String: Any] else {
        bridgeLog("no stdin or no payload")
        exit(0)
    }

    // Build the event payload
    var payload: [String: Any] = [:]

    // Source identification
    payload["_source"] = source

    // Process ID chain for terminal identification
    payload["_ppid"] = ProcessInfo.processInfo.processIdentifier
    if let tty = ProcessInfo.processInfo.environment["TTY"] {
        payload["_tty"] = tty
    }

    // Environment variables for terminal detection
    let env = collectEnvironment()
    for (k, v) in env {
        payload["_env_\(k)"] = v
    }

    // tmux detection
    if env["TMUX"] != nil {
        payload["_tmux_real_bundle_id"] = env["__CFBundleIdentifier"] ?? ""

        // Check for tmux CC clients
        let tmuxBin = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/tmux")
            ? "/opt/homebrew/bin/tmux"
            : "/usr/local/bin/tmux"

        if FileManager.default.fileExists(atPath: tmuxBin) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: tmuxBin)
            proc.arguments = ["list-clients", "-F", "#{client_tty} #{client_control_mode} #{client_pid}"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            payload["_tmux_has_cc_clients"] = output.contains(" 1 ") ? "true" : "false"
        }

        if let pane = env["TMUX_PANE"] {
            payload["_tmux_client_tty"] = pane
        }
    }

    // Map the hook event
    let hookEvent = inputJSON["hook_event_name"] as? String
        ?? inputJSON["event"] as? String
        ?? "Unknown"

    payload["hook_event_name"] = hookEvent

    // Session identification
    let sessionId = inputJSON["session_id"] as? String
        ?? inputJSON["codex_thread_id"] as? String
        ?? "bridge-\(ProcessInfo.processInfo.processIdentifier)"
    payload["session_id"] = sessionId

    // Tool information
    if let toolName = inputJSON["tool_name"] as? String {
        payload["tool_name"] = mapToolName(toolName)
    }
    if let toolInput = inputJSON["tool_input"] {
        payload["tool_input"] = toolInput
    }
    if let toolResponse = inputJSON["tool_response"] {
        payload["tool_response"] = toolResponse
    }
    if let toolUseId = inputJSON["tool_use_id"] {
        payload["tool_use_id"] = toolUseId
    }

    // Prompt and messages
    if let prompt = inputJSON["prompt"] {
        payload["prompt"] = prompt
    }
    if let msg = inputJSON["last_assistant_message"] {
        payload["last_assistant_message"] = msg
    }

    // Status and notification
    if let status = inputJSON["status"] {
        payload["status"] = status
    }
    if let notifType = inputJSON["notification_type"] {
        payload["notification_type"] = notifType
    }
    if let message = inputJSON["message"] {
        payload["message"] = message
    }

    // Working directory
    if let cwd = inputJSON["cwd"] as? String {
        payload["cwd"] = cwd
    } else {
        payload["cwd"] = FileManager.default.currentDirectoryPath
    }

    // Title and model
    if let title = inputJSON["title"] { payload["title"] = title }
    if let model = inputJSON["model"] { payload["model"] = model }

    // Rate limits
    if let rl = inputJSON["rate_limits"] { payload["rate_limits"] = rl }

    // Server port for HTTP-based replies
    if let port = inputJSON["_server_port"] { payload["_server_port"] = port }
    if let reqId = inputJSON["_opencode_request_id"] { payload["_opencode_request_id"] = reqId }

    // Parent/child relationship
    if let parentId = inputJSON["parent_thread_id"] { payload["parent_thread_id"] = parentId }

    // Codex-specific fields
    for key in ["codex_event_type", "codex_thread_id", "codex_title", "codex_model",
                 "codex_permission_mode", "codex_session_start_source",
                 "codex_last_assistant_message", "codex_transcript_path"] {
        if let val = inputJSON[key] { payload[key] = val }
    }

    // Permission mode
    if let pm = inputJSON["permission_mode"] { payload["permission_mode"] = pm }

    // Send to AgentPulse socket
    let response = sendToSocket(payload)

    // If we got a response, output it to stdout for Claude Code to consume
    if let responseData = response {
        if let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            bridgeLog("Response received: \(responseJSON.keys.sorted())")

            if let answersDict = responseJSON["answers"] as? [String: String] {
                // AskUserQuestion answer
                var updatedInput: [String: Any] = ["answers": answersDict]
                if let questions = responseJSON["questions"] {
                    updatedInput["questions"] = questions
                }

                let output: [String: Any] = [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": [
                            "behavior": "allow",
                            "updatedInput": updatedInput
                        ]
                    ]
                ]
                if let outputData = try? JSONSerialization.data(withJSONObject: output) {
                    bridgeLog("Sending answer output: \(outputData.count) bytes")
                    FileHandle.standardOutput.write(outputData)
                }
            } else {
                // Permission reply (allow/deny)
                let allow = responseJSON["allow"] as? Bool ?? false
                let output: [String: Any] = [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": [
                            "behavior": allow ? "allow" : "deny",
                            "reason": "User decision via AgentPulse"
                        ]
                    ]
                ]
                if let outputData = try? JSONSerialization.data(withJSONObject: output) {
                    FileHandle.standardOutput.write(outputData)
                }
            }
        }
    }
}

main()
