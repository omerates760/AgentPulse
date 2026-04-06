// SoundManager.swift — AgentPulse
// System sound playback for agent events

import Foundation
import AppKit

enum SoundEvent: String, CaseIterable {
    case sessionStart
    case sessionEnd
    case permissionRequest
    case permissionApproved
    case permissionDenied
    case question
    case questionAnswered
    case toolStart
    case taskComplete
    case taskError
    case inputRequired
    case resourceLimit
    case compacting

    var systemSoundName: String {
        switch self {
        case .sessionStart:       return "Blow"
        case .sessionEnd:         return "Hero"
        case .permissionRequest:  return "Sosumi"
        case .permissionApproved: return "Purr"
        case .permissionDenied:   return "Basso"
        case .question:           return "Glass"
        case .questionAnswered:   return "Pop"
        case .toolStart:          return "Tink"
        case .taskComplete:       return "Ping"
        case .taskError:          return "Funk"
        case .inputRequired:      return "Morse"
        case .resourceLimit:      return "Basso"
        case .compacting:         return "Tink"
        }
    }
}

class SoundManager {
    static let shared = SoundManager()

    var soundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEnabled") }
    }

    var soundPacksEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "soundPacksEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "soundPacksEnabled") }
    }

    var smartSuppressionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "smartSuppressionEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "smartSuppressionEnabled") }
    }

    /// Bundle identifiers for terminal and code-editor apps that trigger smart suppression.
    private let terminalBundleIds: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92"
    ]

    private init() {}

    func play(_ event: SoundEvent) {
        guard soundEnabled else { return }

        // Smart suppression: skip sound when a terminal / code editor is in focus
        if smartSuppressionEnabled {
            if let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
               terminalBundleIds.contains(frontApp) {
                return
            }
        }

        let soundName = event.systemSoundName
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        }
    }
}
