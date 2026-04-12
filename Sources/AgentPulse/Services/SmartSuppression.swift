// SmartSuppression.swift — AgentPulse
// Single source of truth for the "user is already engaged with the terminal/IDE,
// don't interrupt them" check. Used by SoundManager (silence sounds),
// NotchWindowController (skip panel auto-expand), and RemoteControlService
// (skip Telegram notifications). Glow + status bar badge are NOT suppressed —
// they're passive indicators that don't steal focus.
//
// The check is intentionally global (any-terminal-in-front), not per-session.
// Rationale: if the user is in *any* terminal/IDE they're aware and working;
// jumping to a different window for a notification breaks flow. Per-session
// matching adds complexity (we'd need terminalBundleId on every session) for
// little real benefit.

import Foundation
import AppKit

enum SmartSuppression {
    /// Bundle identifiers for terminals and code editors that count as
    /// "actively engaged" front apps. Adding a new terminal here makes
    /// every consumer of SmartSuppression respect it automatically.
    static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",   // Cursor
    ]

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "smartSuppressionEnabled")
    }

    /// True if the smart-suppression toggle is on AND a terminal/IDE is the
    /// frontmost app right now. Callers should treat a `true` result as
    /// "skip the attention-grabbing action you were about to take".
    static func shouldSuppress() -> Bool {
        guard isEnabled else { return false }
        guard let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return terminalBundleIds.contains(frontApp)
    }
}
