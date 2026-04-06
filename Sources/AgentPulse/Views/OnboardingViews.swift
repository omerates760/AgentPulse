// OnboardingViews.swift — AgentPulse
// Full onboarding flow with animated multi-page experience

import SwiftUI
import AppKit

// MARK: - Onboarding Window Controller

class OnboardingWindowController: NSWindowController {
    var onCloseCallback: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.center()

        self.init(window: window)

        let controller = self
        let view = NSHostingView(rootView: OnboardingView(onComplete: { [weak controller] in
            controller?.close()
        }))
        window.contentView = view
        window.delegate = self
    }

    func showOnboarding() {
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension OnboardingWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onCloseCallback?()
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var currentPage = 0

    // Page 1 animations
    @State private var animateIcon = false
    @State private var animateStats = false
    @State private var gradientPhase: CGFloat = 0.0

    // Page 2 animations
    @State private var animateFeatures = false

    // Page 3 animations
    @State private var animateDetection = false

    // Page 4 animations
    @State private var animateCheckmark = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    environmentPage.tag(2)
                    readyPage.tag(3)
                }
                .tabViewStyle(.automatic)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentPage)

                // Navigation bar
                navigationBar
            }
        }
        .frame(width: 700, height: 520)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button
            if currentPage > 0 {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentPage -= 1
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .medium))
                        Text("Back")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            } else {
                // Invisible placeholder to balance layout
                Text("Back")
                    .font(.system(size: 13))
                    .opacity(0)
            }

            Spacer()

            // Page indicators
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == currentPage ? Color.cyan : Color.white.opacity(0.2))
                        .frame(
                            width: i == currentPage ? 8 : 6,
                            height: i == currentPage ? 8 : 6
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }

            Spacer()

            // Next / Start Vibing button
            if currentPage < 3 {
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        currentPage += 1
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { onComplete() }) {
                    Text("Start Vibing")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.cyan)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 30)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated gradient island icon
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    AngularGradient(
                        gradient: Gradient(colors: [.cyan, .purple, .orange, .cyan]),
                        center: .center,
                        angle: .degrees(gradientPhase)
                    )
                )
                .scaleEffect(animateIcon ? 1.0 : 0.5)
                .opacity(animateIcon ? 1.0 : 0.0)
                .animation(.spring(response: 0.7, dampingFraction: 0.6), value: animateIcon)

            VStack(spacing: 10) {
                Text("AgentPulse")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text("A Dynamic Island for your AI coding tools")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()

            // Stat cards
            HStack(spacing: 16) {
                statCard(value: "13+", label: "terminals")
                statCard(value: "6+", label: "AI agents")
                statCard(value: "0", label: "config needed")
            }
            .opacity(animateStats ? 1.0 : 0.0)
            .offset(y: animateStats ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: animateStats)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 40)
        .onAppear {
            animateIcon = true
            animateStats = true
            // Start continuous gradient rotation
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                gradientPhase = 360.0
            }
        }
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.cyan)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Everything. One glance.")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 20) {
                featureRow(
                    icon: "eye",
                    title: "Permissions at a glance",
                    desc: "See what your agents need without switching windows",
                    index: 0
                )
                featureRow(
                    icon: "hand.tap",
                    title: "Approve without switching",
                    desc: "Allow or deny right from the notch",
                    index: 1
                )
                featureRow(
                    icon: "arrow.up.forward.square",
                    title: "Jump to the exact tab",
                    desc: "Click to jump to the right terminal session",
                    index: 2
                )
                featureRow(
                    icon: "wand.and.stars",
                    title: "Zero config",
                    desc: "Works out of the box, hooks install automatically",
                    index: 3
                )
            }
            .padding(.horizontal, 50)

            Spacer()
        }
        .padding(.horizontal, 20)
        .onAppear {
            animateFeatures = true
        }
    }

    private func featureRow(icon: String, title: String, desc: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
            }
        }
        .opacity(animateFeatures ? 1.0 : 0.0)
        .offset(x: animateFeatures ? 0 : 40)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.75).delay(Double(index) * 0.12),
            value: animateFeatures
        )
    }

    // MARK: - Page 3: Environment Detection

    private var environmentPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Your Environment")
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 20) {
                envSection("AI Agents", items: [
                    ("brain.head.profile", "Claude Code", detectClaude()),
                    ("terminal", "Codex", detectCodex()),
                    ("sparkles", "Gemini CLI", detectGemini()),
                    ("cursorarrow.rays", "Cursor", detectApp("com.todesktop.230313mzl4w4u92")),
                    ("hammer", "Windsurf", detectApp("com.codeium.windsurf")),
                    ("wand.and.stars", "Copilot", detectApp("com.microsoft.VSCode")),
                ], startIndex: 0)

                envSection("Terminals & IDEs", items: [
                    ("terminal", "iTerm2", detectApp("com.googlecode.iterm2")),
                    ("terminal.fill", "Terminal", true),
                    ("bolt.fill", "Warp", detectApp("dev.warp.Warp-Stable")),
                    ("chevron.left.forwardslash.chevron.right", "VS Code", detectApp("com.microsoft.VSCode")),
                    ("hammer.fill", "Xcode", detectApp("com.apple.dt.Xcode")),
                ], startIndex: 6)
            }
            .padding(.horizontal, 50)

            Spacer()
        }
        .padding(.horizontal, 20)
        .onAppear {
            animateDetection = true
        }
    }

    private func envSection(_ title: String, items: [(String, String, Bool)], startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.2)

            ForEach(Array(items.enumerated()), id: \.element.1) { offset, item in
                let (icon, name, detected) = item
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(detected ? .cyan : .white.opacity(0.2))
                        .frame(width: 20)

                    Text(name)
                        .font(.system(size: 13))
                        .foregroundColor(detected ? .white.opacity(0.85) : .white.opacity(0.25))

                    Spacer()

                    if detected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green.opacity(0.8))
                            Text("detected")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.green.opacity(0.7))
                        }
                        .opacity(animateDetection ? 1.0 : 0.0)
                        .animation(
                            .easeOut(duration: 0.35)
                                .delay(Double(startIndex + offset) * 0.1),
                            value: animateDetection
                        )
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    // MARK: - Page 4: Ready

    private var readyPage: some View {
        VStack(spacing: 24) {
            Spacer()

            // Green checkmark with pulsing glow
            ZStack {
                // Glow layer
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .blur(radius: glowPulse ? 30 : 20)
                    .scaleEffect(glowPulse ? 1.2 : 0.9)
                    .animation(
                        .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                        value: glowPulse
                    )

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.green)
                    .scaleEffect(animateCheckmark ? 1.0 : 0.3)
                    .opacity(animateCheckmark ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.5), value: animateCheckmark)
            }

            Text("Ready to Vibe")
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .opacity(animateCheckmark ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.5).delay(0.3), value: animateCheckmark)

            Text("Every running session lives in the notch.\nNo hunting through terminal tabs.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .opacity(animateCheckmark ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.5).delay(0.5), value: animateCheckmark)

            Spacer()

            // Big start button
            Button(action: { onComplete() }) {
                Text("Start Vibing")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.cyan)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 60)
            .padding(.bottom, 8)
            .opacity(animateCheckmark ? 1.0 : 0.0)
            .animation(.easeOut(duration: 0.5).delay(0.7), value: animateCheckmark)
        }
        .padding(.horizontal, 30)
        .onAppear {
            animateCheckmark = true
            glowPulse = true
        }
    }

    // MARK: - Detection Helpers

    private func detectClaude() -> Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude")
    }

    private func detectCodex() -> Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex")
    }

    private func detectGemini() -> Bool {
        FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.gemini")
    }

    private func detectApp(_ bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }
}
