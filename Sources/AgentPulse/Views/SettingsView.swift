// SettingsView.swift — AgentPulse
// Settings panel with general, display, hooks, feedback, and about sections

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: NotchViewModel

    @State private var launchAtLogin = false
    @State private var smartSuppressionEnabled: Bool = UserDefaults.standard.bool(forKey: "smartSuppressionEnabled")
    @State private var feedbackText: String = ""

    // MARK: - Remote Control (Telegram) state

    enum TelegramStatus: Equatable {
        case idle
        case connecting
        case waitingForPairing(botUsername: String)
        case paired
        case error(String)
    }

    @State private var telegramEnabled: Bool = RemoteControlSettings.telegramEnabled
    @State private var telegramToken: String = RemoteControlSecretsStore.telegramToken() ?? ""
    @State private var telegramChatIdDisplay: String = RemoteControlSettings.telegramChatId.map(String.init) ?? ""
    @State private var telegramStatus: TelegramStatus = (RemoteControlSettings.telegramChatId != nil ? .paired : .idle)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {

                // MARK: - General

                settingsSection("General") {
                    toggleRow("Launch at Login", isOn: $launchAtLogin, icon: "power")

                    toggleRow("Sound Effects", isOn: $viewModel.soundEnabled, icon: "speaker.wave.2")

                    VStack(alignment: .leading, spacing: 2) {
                        toggleRow("Smart Suppression", isOn: $smartSuppressionEnabled, icon: "bell.slash")
                            .onChange(of: smartSuppressionEnabled) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "smartSuppressionEnabled")
                            }

                        Text("Don't pop the panel, play sounds, or send Telegram notifications when a terminal/IDE is in focus")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.leading, 22)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // MARK: - Display

                settingsSection("Display") {
                    // Layout picker
                    HStack {
                        Image(systemName: "rectangle.grid.1x2")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 16)
                        Text("Layout")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Picker("", selection: $viewModel.layoutMode) {
                            Text("Clean").tag(LayoutMode.clean)
                            Text("Detailed").tag(LayoutMode.detailed)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    // Modifier key picker
                    HStack {
                        Image(systemName: "keyboard")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 16)
                        Text("Modifier Key")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Picker("", selection: $viewModel.modifierKey) {
                            ForEach(ModifierKeyOption.allCases, id: \.rawValue) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        .frame(width: 120)
                    }

                    // Auto-collapse toggle
                    toggleRow("Auto-collapse on mouse leave",
                              isOn: $viewModel.autoCollapseOnMouseLeave,
                              icon: "rectangle.compress.vertical")
                }

                // MARK: - Hooks

                settingsSection("Hooks") {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(width: 16)
                        Text("Hooks are configured automatically")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.4))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: { HookConfigurator.shared.installAll() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("Reinstall Hooks")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - Remote Control

                settingsSection("Remote Control") {
                    toggleRow("Telegram Bot", isOn: $telegramEnabled, icon: "paperplane")
                        .onChange(of: telegramEnabled) { newValue in
                            RemoteControlSettings.telegramEnabled = newValue
                            RemoteControlService.shared.reloadAdapter(identifier: "telegram")
                            if !newValue { telegramStatus = .idle }
                        }

                    if telegramEnabled {
                        SecureField("Bot token from @BotFather", text: $telegramToken)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(8)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)

                        HStack(spacing: 8) {
                            Button(action: connectTelegram) {
                                HStack(spacing: 4) {
                                    Image(systemName: connectButtonIcon)
                                        .font(.system(size: 9))
                                    Text(connectButtonLabel)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.cyan.opacity(0.12))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .disabled(connectButtonDisabled)
                            .opacity(connectButtonDisabled ? 0.5 : 1.0)

                            if case .paired = telegramStatus {
                                Button(action: unpairTelegram) {
                                    Text("Unpair")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.red.opacity(0.7))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.red.opacity(0.12))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        telegramStatusRow

                        Text("Create a bot via @BotFather on Telegram, paste the token, tap Connect, then send /start to your bot from your phone.")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // MARK: - Feedback

                settingsSection("Feedback") {
                    TextField("Share your thoughts...", text: $feedbackText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)

                    Button(action: sendFeedback) {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 9))
                            Text("Send Feedback")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

                    Text("Or join our community")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))

                    HStack(spacing: 8) {
                        iconLinkButton("link.circle", url: "https://github.com/AuroraEditor/AgentPulse")
                        iconLinkButton("bubble.left.and.bubble.right", url: "https://discord.gg/agentpulse")
                    }
                }

                // MARK: - About

                settingsSection("About") {
                    Text("AgentPulse v1.0.0")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    // License status
                    Button(action: { viewModel.showLicense = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "key")
                                .font(.system(size: 9))
                            Text(LicenseManager.shared.isLicensed ? "Licensed" : "Activate License")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(LicenseManager.shared.isLicensed ? .green : .orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            (LicenseManager.shared.isLicensed ? Color.green : Color.orange).opacity(0.12)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 8) {
                        Button(action: checkForUpdates) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 9))
                                Text("Check for Updates")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Button(action: exportDiagnostics) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 9))
                                Text("Export Diagnostics")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Quit button
                HStack {
                    Spacer()
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Text("Quit AgentPulse")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - Section Builder

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .background(Color.white.opacity(0.04))
            .cornerRadius(8)
        }
    }

    // MARK: - Row Builders

    private func toggleRow(_ label: String, isOn: Binding<Bool>, icon: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }

    private func iconLinkButton(_ systemName: String, url: String) -> some View {
        Button(action: {
            if let link = URL(string: url) {
                NSWorkspace.shared.open(link)
            }
        }) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func sendFeedback() {
        let subject = "AgentPulse Feedback"
        let body = feedbackText.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        if let url = URL(string: "mailto:feedback@agentpulse.app?subject=\(subjectEncoded)&body=\(body)") {
            NSWorkspace.shared.open(url)
            feedbackText = ""
        }
    }

    private func checkForUpdates() {
        if let url = URL(string: "https://agentpulse.app/updates") {
            NSWorkspace.shared.open(url)
        }
    }

    private func exportDiagnostics() {
        let url = DiagnosticLogger.shared.export()
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    // MARK: - Remote Control helpers

    private var connectButtonIcon: String {
        switch telegramStatus {
        case .idle, .error:          return "link"
        case .connecting:            return "ellipsis"
        case .waitingForPairing:     return "hourglass"
        case .paired:                return "checkmark.circle.fill"
        }
    }

    private var connectButtonLabel: String {
        switch telegramStatus {
        case .idle, .error:          return "Connect"
        case .connecting:            return "Connecting…"
        case .waitingForPairing:     return "Waiting for /start…"
        case .paired:                return "Reconnect"
        }
    }

    private var connectButtonDisabled: Bool {
        if telegramToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        switch telegramStatus {
        case .connecting, .waitingForPairing: return true
        default:                              return false
        }
    }

    @ViewBuilder
    private var telegramStatusRow: some View {
        switch telegramStatus {
        case .idle:
            EmptyView()
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Contacting Telegram…")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
        case .waitingForPairing(let botUsername):
            HStack(alignment: .top, spacing: 6) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connected to @\(botUsername)")
                        .font(.system(size: 9))
                        .foregroundColor(.green.opacity(0.8))
                    Text("Open the bot on your phone and send /start to finish pairing.")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .paired:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 10))
                Text("Paired — chat \(telegramChatIdDisplay)")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.6))
            }
        case .error(let msg):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 10))
                Text(msg)
                    .font(.system(size: 9))
                    .foregroundColor(.red.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connectTelegram() {
        let trimmed = telegramToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        RemoteControlSecretsStore.setTelegramToken(trimmed)
        telegramStatus = .connecting

        Task {
            guard let adapter = RemoteControlService.shared.telegramAdapter else {
                await MainActor.run { telegramStatus = .error("Adapter unavailable") }
                return
            }
            do {
                let username = try await adapter.testConnection()
                await MainActor.run { telegramStatus = .waitingForPairing(botUsername: username) }

                if let chatId = try await adapter.discoverChatId() {
                    RemoteControlSettings.telegramChatId = chatId
                    await MainActor.run {
                        telegramChatIdDisplay = String(chatId)
                        telegramStatus = .paired
                    }
                    RemoteControlService.shared.reloadAdapter(identifier: "telegram")
                } else {
                    await MainActor.run {
                        telegramStatus = .error("Pairing timed out. Send /start to your bot and try again.")
                    }
                }
            } catch let err as TelegramError {
                await MainActor.run { telegramStatus = .error(err.errorDescription ?? "Unknown error") }
            } catch {
                await MainActor.run { telegramStatus = .error(error.localizedDescription) }
            }
        }
    }

    private func unpairTelegram() {
        RemoteControlSecretsStore.setTelegramToken(nil)
        RemoteControlSettings.telegramChatId = nil
        telegramToken = ""
        telegramChatIdDisplay = ""
        telegramStatus = .idle
        RemoteControlService.shared.reloadAdapter(identifier: "telegram")
    }
}
