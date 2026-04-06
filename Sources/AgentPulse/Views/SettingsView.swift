// SettingsView.swift — AgentPulse
// Settings panel with general, display, hooks, feedback, and about sections

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: NotchViewModel

    @State private var launchAtLogin = false
    @State private var smartSuppressionEnabled: Bool = UserDefaults.standard.bool(forKey: "smartSuppressionEnabled")
    @State private var feedbackText: String = ""

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

                        Text("Don't play sounds when terminal is in focus")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                            .padding(.leading, 22)
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
}
