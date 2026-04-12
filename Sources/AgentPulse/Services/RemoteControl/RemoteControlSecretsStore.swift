// RemoteControlSecretsStore.swift — AgentPulse
// File-based secrets store for remote-control adapters (Telegram bot token,
// future Discord/Slack tokens, etc.). Replaces the earlier Keychain-based
// store to eliminate the macOS Keychain authorization prompt that fired on
// every rebuild of the ad-hoc-signed binary.
//
// Storage location
//   ~/Library/Application Support/AgentPulse/remote-control.json
//
// Permissions
//   Directory: 0700  (user-only)
//   File:      0600  (user read/write)
//
// Format
//   Pretty-printed JSON with snake_case keys for forward compatibility:
//     { "telegram_token": "..." }
//
// Threat model note
//   This file is plaintext on disk, but only readable by the owning user. The
//   secrets stored here (Telegram bot tokens) are low-value and revocable in
//   30 seconds via @BotFather. If we ever store higher-value secrets (OAuth
//   refresh tokens, payment credentials), reconsider Keychain or encryption.

import Foundation

enum RemoteControlSecretsStore {

    // MARK: - Public API

    static func telegramToken() -> String? {
        load()?.telegramToken
    }

    static func setTelegramToken(_ token: String?) {
        var current = load() ?? Payload()
        if let token = token, !token.isEmpty {
            current.telegramToken = token
        } else {
            current.telegramToken = nil
        }
        save(current)
    }

    // MARK: - Storage

    private struct Payload: Codable {
        var telegramToken: String?
    }

    private static let directoryURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AgentPulse", isDirectory: true)
    }()

    private static let fileURL: URL = directoryURL
        .appendingPathComponent("remote-control.json")

    private static func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(Payload.self, from: data)
    }

    private static func save(_ payload: Payload) {
        do {
            try ensureDirectory()
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            // Atomic write via .atomic option (writes to temp + rename).
            try data.write(to: fileURL, options: [.atomic])
            // Tighten file permissions to 0600 — owner read/write only.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            DiagnosticLogger.shared.log(
                "RemoteControlSecretsStore: save failed: \(error.localizedDescription)"
            )
        }
    }

    private static func ensureDirectory() throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: directoryURL.path, isDirectory: &isDir) {
            try fm.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }
}
