// Analytics.swift — AgentPulse
// Simple counter-based analytics stored in UserDefaults (no external services)

import Foundation

class Analytics {
    static let shared = Analytics()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let enabled = "analyticsEnabled"
        static let approvals = "analytics.approvals"
        static let rejections = "analytics.rejections"
        static let totalSessions = "analytics.totalSessions"
        static let terminalJumps = "analytics.terminalJumps"
        static let questionsAnswered = "analytics.questionsAnswered"
        static let hotkeyToggles = "analytics.hotkeyToggles"
    }

    // MARK: - Enabled

    var analyticsEnabled: Bool {
        get { defaults.object(forKey: Keys.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.enabled) }
    }

    private init() {}

    // MARK: - Tracking

    func trackApproval() {
        guard analyticsEnabled else { return }
        increment(Keys.approvals)
    }

    func trackRejection() {
        guard analyticsEnabled else { return }
        increment(Keys.rejections)
    }

    func trackSession() {
        guard analyticsEnabled else { return }
        increment(Keys.totalSessions)
    }

    func trackTerminalJump() {
        guard analyticsEnabled else { return }
        increment(Keys.terminalJumps)
    }

    func trackQuestionAnswered() {
        guard analyticsEnabled else { return }
        increment(Keys.questionsAnswered)
    }

    func trackHotkeyToggle() {
        guard analyticsEnabled else { return }
        increment(Keys.hotkeyToggles)
    }

    // MARK: - Read Counters

    var approvalCount: Int { defaults.integer(forKey: Keys.approvals) }
    var rejectionCount: Int { defaults.integer(forKey: Keys.rejections) }
    var totalSessionCount: Int { defaults.integer(forKey: Keys.totalSessions) }
    var terminalJumpCount: Int { defaults.integer(forKey: Keys.terminalJumps) }
    var questionsAnsweredCount: Int { defaults.integer(forKey: Keys.questionsAnswered) }
    var hotkeyToggleCount: Int { defaults.integer(forKey: Keys.hotkeyToggles) }

    // MARK: - Reset

    func resetAll() {
        defaults.removeObject(forKey: Keys.approvals)
        defaults.removeObject(forKey: Keys.rejections)
        defaults.removeObject(forKey: Keys.totalSessions)
        defaults.removeObject(forKey: Keys.terminalJumps)
        defaults.removeObject(forKey: Keys.questionsAnswered)
        defaults.removeObject(forKey: Keys.hotkeyToggles)
    }

    // MARK: - Private

    private func increment(_ key: String) {
        let current = defaults.integer(forKey: key)
        defaults.set(current + 1, forKey: key)
    }
}
