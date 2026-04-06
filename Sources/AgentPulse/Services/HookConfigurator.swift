// HookConfigurator.swift — AgentPulse
// Automatically configures hooks for AI coding tools

import Foundation

class HookConfigurator {
    static let shared = HookConfigurator()

    private let bridgePath: String
    private let fm = FileManager.default

    private init() {
        // Bridge is installed at ~/.agent-pulse/bin/agent-pulse-bridge
        bridgePath = NSHomeDirectory() + "/.agent-pulse/bin/agent-pulse-bridge"
    }

    // MARK: - Install All Hooks

    func installAll() {
        installBridge()
        installClaudeHooks()
        installCursorHooks()
        installCodexHooks()
        installGeminiHooks()
        DiagnosticLogger.shared.log("All hooks installed")
    }

    // MARK: - Bridge Installation

    func installBridge() {
        let installDir = NSHomeDirectory() + "/.agent-pulse/bin"

        // Create directory
        try? fm.createDirectory(atPath: installDir, withIntermediateDirectories: true)

        // Find bridge binary in app bundle or build directory
        let candidates = [
            Bundle.main.path(forAuxiliaryExecutable: "agent-pulse-bridge"),
            Bundle.main.resourcePath.map { $0 + "/agent-pulse-bridge" },
            Bundle.main.bundlePath + "/Contents/Helpers/agent-pulse-bridge",
        ].compactMap { $0 }

        for candidate in candidates {
            if fm.fileExists(atPath: candidate) {
                try? fm.removeItem(atPath: bridgePath)
                try? fm.copyItem(atPath: candidate, toPath: bridgePath)
                // Make executable
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bridgePath)
                DiagnosticLogger.shared.log("Bridge installed from \(candidate)")
                return
            }
        }

        // Fallback: create a shell script bridge
        createShellBridge(at: bridgePath)
    }

    // MARK: - Claude Code Hooks

    func installClaudeHooks() {
        let settingsPath = NSHomeDirectory() + "/.claude/settings.json"
        installJSONHooks(
            at: settingsPath,
            source: "claude",
            hookKeys: [
                "hooks": [
                    "PreToolUse": [
                        createHookEntry(source: "claude", event: "PreToolUse")
                    ],
                    "PostToolUse": [
                        createHookEntry(source: "claude", event: "PostToolUse")
                    ],
                    "Notification": [
                        createHookEntry(source: "claude", event: "Notification")
                    ],
                    "Stop": [
                        createHookEntry(source: "claude", event: "Stop")
                    ],
                    "PermissionRequest": [
                        createHookEntryWithMatcher(source: "claude", event: "PermissionRequest", matcher: "*")
                    ],
                    "SessionStart": [
                        createHookEntry(source: "claude", event: "SessionStart")
                    ],
                    "SessionEnd": [
                        createHookEntry(source: "claude", event: "SessionEnd")
                    ],
                    "UserPromptSubmit": [
                        createHookEntry(source: "claude", event: "UserPromptSubmit")
                    ],
                    "SubagentStart": [
                        createHookEntry(source: "claude", event: "SubagentStart")
                    ],
                    "SubagentStop": [
                        createHookEntry(source: "claude", event: "SubagentStop")
                    ],
                    "PreCompact": [
                        createHookEntry(source: "claude", event: "PreCompact")
                    ],
                ]
            ]
        )
    }

    // MARK: - Cursor Hooks

    func installCursorHooks() {
        let settingsPath = NSHomeDirectory() + "/.cursor/hooks.json"
        installJSONHooks(
            at: settingsPath,
            source: "cursor",
            hookKeys: [
                "hooks": [
                    "PreToolUse": [
                        createHookEntry(source: "cursor", event: "PreToolUse")
                    ],
                    "PostToolUse": [
                        createHookEntry(source: "cursor", event: "PostToolUse")
                    ],
                ]
            ]
        )
    }

    // MARK: - Codex Hooks

    func installCodexHooks() {
        let settingsPath = NSHomeDirectory() + "/.codex/hooks.json"
        installJSONHooks(
            at: settingsPath,
            source: "codex",
            hookKeys: [
                "hooks": [
                    "PreToolUse": [
                        createHookEntry(source: "codex", event: "PreToolUse")
                    ],
                    "PostToolUse": [
                        createHookEntry(source: "codex", event: "PostToolUse")
                    ],
                ]
            ]
        )
    }

    // MARK: - Gemini Hooks

    func installGeminiHooks() {
        let settingsPath = NSHomeDirectory() + "/.gemini/settings.json"
        installJSONHooks(
            at: settingsPath,
            source: "gemini",
            hookKeys: [
                "hooks": [
                    "PreToolUse": [
                        createHookEntry(source: "gemini", event: "PreToolUse")
                    ],
                    "PostToolUse": [
                        createHookEntry(source: "gemini", event: "PostToolUse")
                    ],
                ]
            ]
        )
    }

    // MARK: - Private Helpers

    private func createHookEntry(source: String, event: String) -> [String: Any] {
        return createHookEntryWithMatcher(source: source, event: event, matcher: "")
    }

    private func createHookEntryWithMatcher(source: String, event: String, matcher: String) -> [String: Any] {
        let command = "\(bridgePath) --source \(source)"
        return [
            "matcher": matcher,
            "hooks": [
                [
                    "type": "command",
                    "command": command,
                    "description": "AgentPulse: \(event) bridge (do not remove)",
                ]
            ]
        ]
    }

    private func installJSONHooks(at path: String, source: String, hookKeys: [String: Any]) {
        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Read existing settings
        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Merge hooks - preserve existing non-agent-pulse hooks
        if let newHooks = hookKeys["hooks"] as? [String: Any] {
            var existingHooks = settings["hooks"] as? [String: Any] ?? [:]

            for (eventName, newEntries) in newHooks {
                guard let newList = newEntries as? [[String: Any]] else { continue }
                var eventHooks = existingHooks[eventName] as? [[String: Any]] ?? []

                // Remove existing agent-pulse entries (check nested hooks array)
                eventHooks.removeAll { matcherEntry in
                    if let innerHooks = matcherEntry["hooks"] as? [[String: Any]] {
                        return innerHooks.contains { hook in
                            let desc = hook["description"] as? String ?? ""
                            let cmd = hook["command"] as? String ?? ""
                            return desc.contains("AgentPulse") || cmd.contains("agent-pulse-bridge")
                        }
                    }
                    // Also check flat format (legacy)
                    let desc = matcherEntry["description"] as? String ?? ""
                    let cmd = matcherEntry["command"] as? String ?? ""
                    return desc.contains("AgentPulse") || cmd.contains("agent-pulse-bridge")
                }

                // Add new entries
                eventHooks.append(contentsOf: newList)
                existingHooks[eventName] = eventHooks
            }

            settings["hooks"] = existingHooks
        }

        // Write back
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            // Backup existing file
            if fm.fileExists(atPath: path) {
                try? fm.copyItem(atPath: path, toPath: path + ".backup")
            }
            try? data.write(to: URL(fileURLWithPath: path))
            DiagnosticLogger.shared.log("Hooks installed for \(source) at \(path)")
        }
    }

    private func createShellBridge(at path: String) {
        let script = """
        #!/bin/bash
        # agent-pulse-bridge launcher (auto-generated, do not edit)
        #  Auto-configured by AgentPulse (https://agentpulse.app)

        # Find the actual bridge binary
        H="/Contents/Helpers/agent-pulse-bridge"
        C=~/.agent-pulse/bin/.bridge-cache

        # Check cached path first
        if [ -f "$C" ] && [ -x "$(cat "$C")" ]; then
            exec "$(cat "$C")" "$@"
        fi

        # Search in running app
        APP=$(mdfind "kMDItemCFBundleIdentifier == 'com.agentpulse.app'" 2>/dev/null | head -1)
        if [ -n "$APP" ] && [ -x "${APP}${H}" ]; then
            echo "${APP}${H}" > "$C"
            exec "${APP}${H}" "$@"
        fi

        # Fallback: pipe stdin to socket
        if [ -S /tmp/agent-pulse.sock ]; then
            cat | socat - UNIX-CONNECT:/tmp/agent-pulse.sock 2>/dev/null
        else
            echo "agent-pulse-bridge: app not found. Launch AgentPulse once to fix." >&2
        fi
        """

        try? script.write(toFile: path, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        DiagnosticLogger.shared.log("Shell bridge created at \(path)")
    }
}
