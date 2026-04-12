// AppDelegate.swift — AgentPulse
// Main application delegate

import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var notchWindowController: NotchWindowController?
    var onboardingController: OnboardingWindowController?
    var licenseWindowController: LicenseWindowController?

    private let sessionStore = SessionStore.shared
    private var cancellables = Set<AnyCancellable>()
    private let viewModel = NotchViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup status bar item
        setupStatusItem()

        // Create notch panel
        setupNotchPanel()

        // Start socket server
        sessionStore.start()

        // Start remote control (Telegram, etc.) — must be after sessionStore
        // so its Combine subscriptions see a fully initialized store.
        RemoteControlService.shared.start()

        // Install hooks
        HookConfigurator.shared.installAll()

        // Setup keyboard shortcuts
        setupKeyboardShortcuts()

        // Check onboarding
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showOnboarding()
            }
        } else {
            // Already onboarded — show and expand panel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.notchWindowController?.positionPanel()
                self.notchWindowController?.expand()
            }
        }

        // Observe session changes for status item updates
        observeSessionChanges()

        DiagnosticLogger.shared.log("AgentPulse launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        sessionStore.saveSessions()
        RemoteControlService.shared.stop()
        sessionStore.stop()
        KeyboardShortcutManager.shared.unregister()
        DiagnosticLogger.shared.log("AgentPulse terminated")
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "AgentPulse")
            button.image?.size = NSSize(width: 16, height: 16)
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleNotchPanel()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Panel", action: #selector(toggleNotchPanel), keyEquivalent: "")
        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.state = UserDefaults.standard.bool(forKey: "launchAtLogin") ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "License", action: #selector(showLicenseWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AgentPulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Notch Panel

    private func setupNotchPanel() {
        notchWindowController = NotchWindowController(viewModel: viewModel)
        notchWindowController?.show()
    }

    @objc func toggleNotchPanel() {
        notchWindowController?.toggleExpansion()
    }

    // MARK: - Keyboard Shortcuts

    private func setupKeyboardShortcuts() {
        KeyboardShortcutManager.shared.onTogglePanel = { [weak self] in
            self?.toggleNotchPanel()
        }
        KeyboardShortcutManager.shared.register()
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        onboardingController = OnboardingWindowController()
        onboardingController?.showOnboarding()

        // Watch for onboarding completion to show the notch panel
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: onboardingController?.window,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.notchWindowController?.positionPanel()
                self?.notchWindowController?.show()
                self?.notchWindowController?.expand()
            }
        }
    }

    // MARK: - Settings & License

    @objc private func showSettings() {
        viewModel.selectedTab = .settings
        viewModel.expand()
    }

    @objc private func showLicenseWindow() {
        licenseWindowController = LicenseWindowController()
        licenseWindowController?.showLicense()
    }

    @objc private func toggleLaunchAtLogin() {
        let current = UserDefaults.standard.bool(forKey: "launchAtLogin")
        UserDefaults.standard.set(!current, forKey: "launchAtLogin")
    }

    // MARK: - Session Observation

    private func observeSessionChanges() {
        sessionStore.$sessions
            .combineLatest(sessionStore.$activePermissions, sessionStore.$activeQuestions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions, perms, questions in
                self?.updateStatusItemIcon(sessions: sessions, perms: perms, questions: questions)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItemIcon(sessions: [Session], perms: [PermissionRequest], questions: [QuestionRequest]) {
        guard let button = statusItem.button else { return }

        let iconName: String
        let tintColor: NSColor
        let badgeCount = perms.count + questions.count

        if !perms.isEmpty {
            iconName = "exclamationmark.circle.fill"
            tintColor = .systemOrange
        } else if !questions.isEmpty {
            iconName = "questionmark.circle.fill"
            tintColor = .systemPurple
        } else if sessions.contains(where: { $0.isActive }) {
            iconName = "circle.hexagongrid.fill"
            tintColor = .systemCyan
        } else {
            iconName = "circle.hexagongrid"
            tintColor = .labelColor
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "AgentPulse")
            button.image?.size = NSSize(width: 16, height: 16)
            button.image?.isTemplate = true
            button.contentTintColor = nil
            button.title = ""
            NSApp.dockTile.badgeLabel = nil
            return
        }

        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "AgentPulse")?
            .withSymbolConfiguration(config)
        button.image?.isTemplate = false
        button.contentTintColor = tintColor

        // Badge count on status bar
        if badgeCount > 0 {
            button.title = " \(badgeCount)"
            let attrTitle = NSMutableAttributedString(string: " \(badgeCount)")
            attrTitle.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                .foregroundColor: tintColor,
            ], range: NSRange(location: 0, length: attrTitle.length))
            button.attributedTitle = attrTitle
        } else {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
        }
    }
}
