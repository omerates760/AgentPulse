// TerminalJumper.swift — AgentPulse
// Jumps to the correct terminal window/tab for a session via AppleScript

import Foundation
import AppKit

class TerminalJumper {
    static let shared = TerminalJumper()

    private init() {}

    func jumpToSession(_ session: Session) {
        let bundleId = detectTerminalApp(for: session)
        DiagnosticLogger.shared.log("Jumping to session \(session.id) via \(bundleId)")

        switch bundleId {
        case "com.googlecode.iterm2":
            jumpToITerm2(session)
        case "com.apple.Terminal":
            jumpToAppleTerminal(session)
        case "com.microsoft.VSCode":
            jumpToVSCode(session)
        case "com.todesktop.230313mzl4w4u92":
            jumpToCursor(session)
        case "dev.warp.Warp-Stable":
            jumpToWarp(session)
        case "com.mitchellh.ghostty":
            jumpToGhostty(session)
        case "net.kovidgoyal.kitty":
            jumpToKitty(session)
        default:
            activateApp(bundleId: bundleId)
        }
    }

    // MARK: - Terminal Detection

    private func detectTerminalApp(for session: Session) -> String {
        // Use stored terminal bundle ID from hook event
        if let bundleId = session.terminalBundleId, !bundleId.isEmpty {
            DiagnosticLogger.shared.log("Terminal from session: \(bundleId)")
            return bundleId
        }

        // Check agent type hints
        if session.agentType == .cursor {
            return "com.todesktop.230313mzl4w4u92"
        }

        // Default to Apple Terminal
        return "com.apple.Terminal"
    }

    // MARK: - iTerm2

    private func jumpToITerm2(_ session: Session) {
        let script = """
        tell application "iTerm2"
            activate
            tell current window
                select
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Apple Terminal

    private func jumpToAppleTerminal(_ session: Session) {
        let script = """
        tell application "Terminal"
            activate
            if (count of windows) > 0 then
                set frontWindow to front window
                set index of frontWindow to 1
            end if
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - VS Code

    private func jumpToVSCode(_ session: Session) {
        if let cwd = session.cwd, let url = URL(string: "vscode://file/\(cwd)") {
            NSWorkspace.shared.open(url)
        } else {
            activateApp(bundleId: "com.microsoft.VSCode")
        }
    }

    // MARK: - Cursor

    private func jumpToCursor(_ session: Session) {
        if let cwd = session.cwd, let url = URL(string: "cursor://file/\(cwd)") {
            NSWorkspace.shared.open(url)
        } else {
            activateApp(bundleId: "com.todesktop.230313mzl4w4u92")
        }
    }

    // MARK: - Warp

    private func jumpToWarp(_ session: Session) {
        activateApp(bundleId: "dev.warp.Warp-Stable")
    }

    // MARK: - Ghostty

    private func jumpToGhostty(_ session: Session) {
        activateApp(bundleId: "com.mitchellh.ghostty")
    }

    // MARK: - Kitty

    private func jumpToKitty(_ session: Session) {
        activateApp(bundleId: "net.kovidgoyal.kitty")
    }

    // MARK: - Helpers

    private func activateApp(bundleId: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            DiagnosticLogger.shared.log("App not found: \(bundleId)")
            return
        }

        // For Apple Terminal, use AppleScript which is more reliable
        if bundleId == "com.apple.Terminal" {
            let script = """
            tell application "Terminal"
                activate
                if (count of windows) > 0 then
                    set index of front window to 1
                end if
            end tell
            """
            runAppleScript(script)
            return
        }

        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    /// Type text into the active terminal and press Enter
    func typeInTerminal(_ session: Session, text: String) {
        let bundleId = detectTerminalApp(for: session)
        DiagnosticLogger.shared.log("Typing in terminal \(bundleId): \(text)")
        activateApp(bundleId: bundleId)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "System Events"
                keystroke "\(escaped)"
                delay 0.1
                keystroke return
            end tell
            """
            self.runAppleScript(script)
        }
    }

    /// Select an option in Claude Code's AskUserQuestion by arrow keys
    /// optionIndex is 0-based (how many arrow-downs from the first option)
    func selectOptionInTerminal(_ session: Session, optionIndex: Int) {
        let bundleId = detectTerminalApp(for: session)
        DiagnosticLogger.shared.log("Selecting option \(optionIndex) in terminal \(bundleId)")
        activateApp(bundleId: bundleId)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            var arrowPresses = ""
            for _ in 0..<optionIndex {
                arrowPresses += """
                    key code 125
                    delay 0.05

                """
            }
            let script = """
            tell application "System Events"
                \(arrowPresses)
                delay 0.1
                keystroke return
            end tell
            """
            DiagnosticLogger.shared.log("AppleScript select: \(optionIndex) arrows + enter")
            self.runAppleScript(script)
        }
    }

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
                if let error = error {
                    DiagnosticLogger.shared.log("AppleScript error: \(error)")
                }
            }
        }
    }
}
