// NotchViewModel.swift — AgentPulse
// Main view model for the notch panel

import Foundation
import Combine
import AppKit
import SwiftUI

class NotchViewModel: ObservableObject {
    // MARK: - Panel State
    @Published var isExpanded = false
    @Published var isHovered = false
    @Published var isPanelHovered = false
    @Published var isModifierHeld = false
    @Published var expandedHeight: CGFloat = 400

    // MARK: - Session State (derived from SessionStore)
    @Published var sessions: [Session] = []
    @Published var activePermissions: [PermissionRequest] = []
    @Published var activeQuestions: [QuestionRequest] = []

    // MARK: - UI State
    @Published var selectedTab: PanelTab = .sessions
    @Published var layoutMode: LayoutMode = .detailed
    @Published var showOnboarding = false
    @Published var showSettings = false
    @Published var showLicense = false

    // MARK: - Settings
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }
    @Published var autoCollapseOnMouseLeave: Bool {
        didSet { UserDefaults.standard.set(autoCollapseOnMouseLeave, forKey: "autoCollapseOnMouseLeave") }
    }
    @Published var modifierKey: ModifierKeyOption {
        didSet { UserDefaults.standard.set(modifierKey.rawValue, forKey: "modifierKey") }
    }

    enum PanelTab: String, CaseIterable {
        case sessions = "Sessions"
        case settings = "Settings"
    }

    private let sessionStore = SessionStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var autoCollapseTimer: Timer?
    var onExpandChanged: ((Bool) -> Void)?
    var onInteraction: (() -> Void)?

    init() {
        self.soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
        self.autoCollapseOnMouseLeave = UserDefaults.standard.object(forKey: "autoCollapseOnMouseLeave") as? Bool ?? true
        let modKey = UserDefaults.standard.string(forKey: "modifierKey") ?? "option"
        self.modifierKey = ModifierKeyOption(rawValue: modKey) ?? .option
        let layout = UserDefaults.standard.string(forKey: "layoutMode") ?? "detailed"
        self.layoutMode = LayoutMode(rawValue: layout) ?? .detailed

        bindToSessionStore()
    }

    // MARK: - Panel Actions

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        autoCollapseTimer?.invalidate()
        onExpandChanged?(true)
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        selectedTab = .sessions
        onExpandChanged?(false)
    }

    func toggleExpansion() {
        if isExpanded { collapse() } else { expand() }
    }

    func mouseEntered() {
        isHovered = true
        autoCollapseTimer?.invalidate()
        expand()
    }

    func mouseExited() {
        isHovered = false
        if autoCollapseOnMouseLeave {
            scheduleAutoCollapse()
        }
    }

    func panelMouseEntered() {
        isPanelHovered = true
        autoCollapseTimer?.invalidate()
    }

    func panelMouseExited() {
        isPanelHovered = false
        if !isHovered && autoCollapseOnMouseLeave {
            scheduleAutoCollapse()
        }
    }

    // MARK: - Permission Actions

    func approvePermission(_ permission: PermissionRequest) {
        onInteraction?()
        sessionStore.approvePermission(permission)
        Analytics.shared.trackApproval()
    }

    func alwaysAllowPermission(_ permission: PermissionRequest) {
        onInteraction?()
        sessionStore.alwaysAllowPermission(permission)
        Analytics.shared.trackApproval()
    }

    func denyPermission(_ permission: PermissionRequest) {
        onInteraction?()
        sessionStore.denyPermission(permission)
        Analytics.shared.trackRejection()
    }

    // MARK: - Question Actions

    // Tracks selected answers for multi-question batches
    var pendingAnswers: [String: String] = [:] // questionId -> answer

    func answerQuestion(_ question: QuestionRequest, answer: String) {
        onInteraction?()
        let sessionQuestions = activeQuestions.filter { $0.sessionId == question.sessionId }

        if sessionQuestions.count <= 1 {
            // Single question — send immediately
            DispatchQueue.main.async { [weak self] in
                self?.sessionStore.answerQuestion(question, answer: answer)
            }
        } else {
            // Multi question — store answer, wait for submit
            pendingAnswers[question.id] = answer
            objectWillChange.send()
        }
    }

    func submitAllAnswers(sessionId: String) {
        onInteraction?()
        let sessionQuestions = activeQuestions.filter { $0.sessionId == sessionId }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for q in sessionQuestions {
                let answer = self.pendingAnswers[q.id] ?? ""
                if !answer.isEmpty {
                    self.sessionStore.answerQuestion(q, answer: answer)
                }
            }
            self.pendingAnswers.removeAll()
        }
    }

    func allQuestionsAnswered(sessionId: String) -> Bool {
        let sessionQuestions = activeQuestions.filter { $0.sessionId == sessionId }
        return sessionQuestions.allSatisfy { pendingAnswers[$0.id] != nil }
    }

    func answeredCount(sessionId: String) -> Int {
        let sessionQuestions = activeQuestions.filter { $0.sessionId == sessionId }
        return sessionQuestions.filter { pendingAnswers[$0.id] != nil }.count
    }

    func answerInTerminal(_ question: QuestionRequest) {
        sessionStore.answerQuestionInTerminal(question)
        Analytics.shared.trackTerminalJump()
    }

    // MARK: - Session Actions

    func jumpToSession(_ session: Session) {
        TerminalJumper.shared.jumpToSession(session)
        Analytics.shared.trackTerminalJump()
    }

    func hideSession(_ session: Session) {
        sessionStore.hideSession(session)
    }

    // MARK: - Computed

    var activeSessions: [Session] {
        sessions.filter { $0.isActive && !$0.isHidden }
    }

    var endedSessions: [Session] {
        sessions.filter { !$0.isActive && !$0.isHidden }
    }

    var sessionCount: Int { activeSessions.count }

    var needsAttentionCount: Int {
        sessions.filter { $0.needsAttention }.count
    }

    var hasAnyContent: Bool {
        !sessions.isEmpty || !activePermissions.isEmpty || !activeQuestions.isEmpty
    }

    var collapsedStatusText: String {
        let count = activeSessions.count
        if count == 0 { return "" }
        if let perm = activePermissions.first {
            return perm.displayDescription
        }
        if activeQuestions.first != nil {
            return "Question"
        }
        return "\(count) session\(count == 1 ? "" : "s")"
    }

    var collapsedStatusColor: NSColor {
        if !activePermissions.isEmpty { return .systemOrange }
        if !activeQuestions.isEmpty { return .systemPurple }
        if activeSessions.isEmpty { return .systemGray }
        return .systemCyan
    }

    // MARK: - Calculate Panel Height

    var calculatedExpandedHeight: CGFloat {
        var height: CGFloat = 52 // header

        // Permissions
        if !activePermissions.isEmpty {
            height += CGFloat(activePermissions.count) * 120
        }

        // Questions
        if !activeQuestions.isEmpty {
            height += CGFloat(activeQuestions.count) * 140
        }

        // Sessions
        let visibleCount = min(activeSessions.count, 6)
        height += CGFloat(visibleCount) * (layoutMode == .detailed ? 72 : 52)

        // Ended sessions
        if !endedSessions.isEmpty {
            height += 40
        }

        // Minimum
        height = max(height, 120)

        // Maximum
        let maxHeight = UserDefaults.standard.double(forKey: "maxPanelHeight")
        let maxH = maxHeight > 0 ? CGFloat(maxHeight) : 700
        return min(height, maxH)
    }

    // MARK: - Private

    private func bindToSessionStore() {
        sessionStore.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSessions in
                guard let self = self else { return }
                self.sessions = newSessions
            }
            .store(in: &cancellables)

        sessionStore.$activePermissions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] perms in
                self?.activePermissions = perms
            }
            .store(in: &cancellables)

        sessionStore.$activeQuestions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] questions in
                self?.activeQuestions = questions
            }
            .store(in: &cancellables)

        // Auto-expand is handled by NotchWindowController (with SmartSuppression).
        // ViewModel must NOT expand independently — it would cause a state mismatch
        // where viewModel.isExpanded=true but the physical panel is still collapsed.
    }

    private func scheduleAutoCollapse() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !self.isHovered && !self.isPanelHovered {
                self.collapse()
            }
        }
    }
}
