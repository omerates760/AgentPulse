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

    // MARK: - Init

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        self.notchPanel = NotchPanel()
        super.init(window: notchPanel)

        setupHostingView()
        observeViewModel()
        observeScreenChanges()
        observeGlow()

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
        notchPanel.setHostingView(NSHostingView(rootView: rootView))
    }

    // MARK: - ViewModel Observation

    private func observeViewModel() {
        SessionStore.shared.$activePermissions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] perms in if !perms.isEmpty { self?.expand() } }
            .store(in: &cancellables)

        SessionStore.shared.$activeQuestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] qs in if !qs.isEmpty { self?.expand() } }
            .store(in: &cancellables)

        SessionStore.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                guard let self else { return }
                let active = sessions.filter { $0.isActive && !$0.isHidden }
                // Update pill width
                self.notchPanel.updateCollapsedState(hasActive: !active.isEmpty)
                // Auto-expand on first session
                if !active.isEmpty && !self.notchPanel.isExpanded { self.expand() }
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
}
