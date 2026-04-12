// NotchWindowController.swift — AgentPulse
// Manages NotchPanel lifecycle, glow effects, and expansion

import AppKit
import SwiftUI
import Combine

final class NotchWindowController: NSWindowController {

    let notchPanel: NotchPanel
    let viewModel: NotchViewModel

    private var cancellables = Set<AnyCancellable>()
    private var clickOutsideMonitor: Any?
    private var fullscreenTimer: Timer?
    private var isInFullscreen: Bool = false

    // MARK: - Init

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.notchPanel = NotchPanel()
        super.init(window: notchPanel)

        setupHostingView()
        observeViewModel()
        observeScreenChanges()
        observeGlow()
        startFullscreenObserver()

        notchPanel.onHoverChanged = { [weak self] isInside in
            guard let self else { return }
            if isInside && !self.notchPanel.isExpanded {
                self.expand()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        fullscreenTimer?.invalidate()
        removeClickOutsideMonitor()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Show / Hide

    func show() {
        positionPanel()
        notchPanel.orderFrontRegardless()
    }

    func hide() { notchPanel.orderOut(nil) }
    func showPanel() { show() }

    // MARK: - Expand / Collapse

    func toggleExpansion() {
        if notchPanel.isExpanded { collapse() } else { expand() }
    }

    func expand() {
        notchPanel.expand()
        viewModel.isExpanded = true
        installClickOutsideMonitor()
    }

    func collapse() {
        notchPanel.collapse()
        viewModel.isExpanded = false
        removeClickOutsideMonitor()
    }

    // MARK: - Click Outside

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.notchPanel.isExpanded else { return }
            let pt = NSEvent.mouseLocation
            if !self.notchPanel.frame.contains(pt) {
                DispatchQueue.main.async { self.collapse() }
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let m = clickOutsideMonitor { NSEvent.removeMonitor(m); clickOutsideMonitor = nil }
    }

    // MARK: - Positioning

    func positionPanel() {
        let screen = ScreenSelector.screenWithNotch() ?? NSScreen.main ?? NSScreen.screens.first!
        notchPanel.positionOnScreen(screen)
    }

    // MARK: - Hosting View

    private func setupHostingView() {
        let rootView = NotchContentView(viewModel: viewModel).environment(\.colorScheme, .dark)
        notchPanel.setHostingView(NotchHostingView(rootView: rootView))
    }

    // MARK: - ViewModel Observation

    private func observeViewModel() {
        SessionStore.shared.$activePermissions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] perms in
                if !perms.isEmpty && !SmartSuppression.shouldSuppress() {
                    self?.expand()
                }
            }
            .store(in: &cancellables)

        SessionStore.shared.$activeQuestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] qs in
                if !qs.isEmpty && !SmartSuppression.shouldSuppress() {
                    self?.expand()
                }
            }
            .store(in: &cancellables)

        SessionStore.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                let active = sessions.filter { $0.isActive && !$0.isHidden }
                // Update pill width — does not expand the panel.
                // Auto-expand is reserved for permission/question events, which
                // genuinely need attention. New sessions just start activity.
                self.notchPanel.updateCollapsedState(hasActive: !active.isEmpty)
            }
            .store(in: &cancellables)
    }

    // MARK: - Glow Effect

    private func observeGlow() {
        // Update glow based on session state
        SessionStore.shared.$activePermissions
            .combineLatest(SessionStore.shared.$activeQuestions, SessionStore.shared.$sessions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] perms, questions, sessions in
                guard let self, !self.notchPanel.isExpanded else {
                    self?.notchPanel.updateGlow(color: .clear, intensity: 0)
                    return
                }
                if !perms.isEmpty {
                    self.notchPanel.updateGlow(color: .systemOrange, intensity: 0.6)
                } else if !questions.isEmpty {
                    self.notchPanel.updateGlow(color: .systemPurple, intensity: 0.6)
                } else if sessions.contains(where: { $0.isActive }) {
                    self.notchPanel.updateGlow(color: .systemCyan, intensity: 0.3)
                } else {
                    self.notchPanel.updateGlow(color: .clear, intensity: 0)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Screen Changes

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleScreenChange),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func handleScreenChange(_ n: Notification) { positionPanel() }

    // MARK: - Fullscreen Handling

    private func startFullscreenObserver() {
        // Primary: space change notification (fires on fullscreen enter/exit)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
        // Backup: periodic poll for edge cases
        fullscreenTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkFullscreen()
        }
    }

    @objc private func spaceChanged(_ n: Notification) {
        checkFullscreen()
    }

    private func checkFullscreen() {
        let isFS = isAnyAppFullscreen()
        guard isFS != isInFullscreen else { return }
        isInFullscreen = isFS
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if isFS {
                self.notchPanel.orderOut(nil)
            } else {
                self.positionPanel()
                self.notchPanel.orderFrontRegardless()
            }
        }
    }

    private func isAnyAppFullscreen() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = frontApp.processIdentifier

        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let screenFrame = screen.frame

        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? Int32,
                  ownerPID == pid,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let windowWidth = boundsDict["Width"] ?? 0
            let windowHeight = boundsDict["Height"] ?? 0
            if windowWidth >= screenFrame.width && windowHeight >= screenFrame.height {
                return true
            }
        }
        return false
    }
}
