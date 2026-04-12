// TerminalJumper.swift — AgentPulse
// Jumps to the correct terminal window/tab for a session

import Foundation
import AppKit

class TerminalJumper {
    static let shared = TerminalJumper()

    private init() {}

    func jumpToSession(_ session: Session) {
        let bundleId = detectTerminalApp(for: session)
        DiagnosticLogger.shared.log("Jumping to session \(session.id) via \(bundleId)")

        // If session is in tmux, select the right pane first
        if let tmuxPane = session.tmuxPane {
            jumpToTmux(pane: tmuxPane)
        }

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
            activateApp(bundleId: bundleId)
        case "com.mitchellh.ghostty":
            jumpToGhostty(session)
        case "net.kovidgoyal.kitty":
            jumpToKitty(session)
        case "org.wezfurlong.wezterm":
            jumpToWezTerm(session)
        default:
            activateApp(bundleId: bundleId)
        }
    }

    // MARK: - Terminal Detection

    private func detectTerminalApp(for session: Session) -> String {
        if let bundleId = session.terminalBundleId, !bundleId.isEmpty {
            return bundleId
        }
        if session.agentType == .cursor {
            return "com.todesktop.230313mzl4w4u92"
        }
        return "com.apple.Terminal"
    }

    // MARK: - iTerm2 (tab-level matching)

    private func jumpToITerm2(_ session: Session) {
        guard let sessionId = session.terminalSessionId else {
            activateApp(bundleId: "com.googlecode.iterm2")
            return
        }
        // ITERM_SESSION_ID format: "w0t0p0:GUID" — extract the GUID
        let uniqueId = sessionId.split(separator: ":").last.map(String.init) ?? sessionId
        let escaped = uniqueId.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "iTerm2"
            activate
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if unique ID of aSession contains "\(escaped)" then
                            select aTab
                            tell aWindow to select
                            select aSession
                            return
                        end if
                    end repeat
                end repeat
            end repeat
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

    // MARK: - Ghostty (window title matching)

    private func jumpToGhostty(_ session: Session) {
        if let cwd = session.cwd {
            let projectDir = cwd.split(separator: "/").last.map(String.init) ?? cwd
            let escaped = projectDir.replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            tell application "Ghostty"
                activate
                set allWindows to every window
                repeat with w in allWindows
                    if name of w contains "\(escaped)" then
                        set index of w to 1
                        return
                    end if
                end repeat
            end tell
            """
            runAppleScript(script)
        } else {
            activateApp(bundleId: "com.mitchellh.ghostty")
        }
    }

    // MARK: - Kitty (remote control)

    private func jumpToKitty(_ session: Session) {
        guard let windowId = session.kittyWindowId else {
            activateApp(bundleId: "net.kovidgoyal.kitty")
            return
        }
        if let kittenBin = findExecutable("kitten") ?? findExecutable("kitty") {
            let args = kittenBin.hasSuffix("kitten")
                ? ["@", "focus-window", "--match", "id:\(windowId)"]
                : ["@", "focus-window", "--match", "id:\(windowId)"]
            runProcess(kittenBin, arguments: args)
        }
        activateApp(bundleId: "net.kovidgoyal.kitty")
    }

    // MARK: - WezTerm (CLI tab matching)

    private func jumpToWezTerm(_ session: Session) {
        guard let cwd = session.cwd,
              let weztermBin = findExecutable("wezterm") else {
            activateApp(bundleId: "org.wezfurlong.wezterm")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let (output, _) = self.runProcessSync(weztermBin, arguments: ["cli", "list", "--format", "json"])
            if let data = output?.data(using: .utf8),
               let panes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for pane in panes {
                    if let paneCwd = pane["cwd"] as? String, paneCwd == cwd,
                       let tabId = pane["tab_id"] as? Int {
                        self.runProcessSync(weztermBin, arguments: ["cli", "activate-tab", "--tab-id", "\(tabId)"])
                        break
                    }
                }
            }
            DispatchQueue.main.async {
                self.activateApp(bundleId: "org.wezfurlong.wezterm")
            }
        }
    }

    // MARK: - tmux (pane selection)

    private func jumpToTmux(pane: String) {
        guard let tmuxBin = findExecutable("tmux") else { return }
        runProcess(tmuxBin, arguments: ["select-window", "-t", pane])
        runProcess(tmuxBin, arguments: ["select-pane", "-t", pane])
    }

    // MARK: - Helpers

    private func activateApp(bundleId: String) {
        if bundleId == "com.apple.Terminal" {
            jumpToAppleTerminal(Session(id: "", agentType: .unknown))
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            DiagnosticLogger.shared.log("App not found: \(bundleId)")
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

    // MARK: - Process Helpers

    private func findExecutable(_ name: String) -> String? {
        let paths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return paths.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func runProcess(_ path: String, arguments: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard FileManager.default.fileExists(atPath: path) else { return }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = arguments
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            try? proc.run()
            proc.waitUntilExit()
        }
    }

    @discardableResult
    private func runProcessSync(_ path: String, arguments: [String]) -> (String?, Int32) {
        guard FileManager.default.fileExists(atPath: path) else { return (nil, -1) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8), proc.terminationStatus)
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
