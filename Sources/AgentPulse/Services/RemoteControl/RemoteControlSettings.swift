// RemoteControlSettings.swift — AgentPulse
// UserDefaults-backed settings for remote control adapters.
// Secrets (bot tokens) live in RemoteControlSecretsStore (a file under
// ~/Library/Application Support/AgentPulse), not here.

import Foundation

enum RemoteControlSettings {
    private static let keyTelegramEnabled = "remoteControl.telegram.enabled"
    private static let keyTelegramChatId  = "remoteControl.telegram.chatId"

    // MARK: - Telegram

    static var telegramEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: keyTelegramEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: keyTelegramEnabled) }
    }

    /// Paired chat id (numeric). Nil when unpaired.
    static var telegramChatId: Int64? {
        get {
            guard let raw = UserDefaults.standard.object(forKey: keyTelegramChatId) as? NSNumber else {
                return nil
            }
            return raw.int64Value
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(NSNumber(value: v), forKey: keyTelegramChatId)
            } else {
                UserDefaults.standard.removeObject(forKey: keyTelegramChatId)
            }
        }
    }

    /// Wipes all Telegram settings. Does NOT touch the stored token —
    /// callers should call RemoteControlSecretsStore.setTelegramToken(nil) too.
    static func clearTelegram() {
        UserDefaults.standard.removeObject(forKey: keyTelegramEnabled)
        UserDefaults.standard.removeObject(forKey: keyTelegramChatId)
    }
}
