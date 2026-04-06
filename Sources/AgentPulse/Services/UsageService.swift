// UsageService.swift — AgentPulse
// Tracks API usage and rate limit information from sessions

import Foundation
import Combine

class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published var currentUsage: RateLimits?

    private init() {}

    func updateFromSession(_ session: Session) {
        if let rateLimits = session.rateLimits {
            DispatchQueue.main.async {
                self.currentUsage = rateLimits
            }
        }
    }

    var displayString: String {
        guard let usage = currentUsage else { return "No usage data" }

        let primary = Int(usage.primaryUsedPercent)
        var result = "API Usage: \(primary)%"

        if let secondary = usage.secondaryUsedPercent {
            let sec = Int(secondary)
            result += " | Secondary: \(sec)%"
        }

        if let resetsAt = usage.primaryResetsAt {
            result += " (resets \(resetsAt))"
        }

        return result
    }

    var isNearLimit: Bool {
        guard let usage = currentUsage else { return false }
        return usage.primaryUsedPercent >= 80
    }

    var isAtLimit: Bool {
        guard let usage = currentUsage else { return false }
        return usage.primaryUsedPercent >= 95
    }
}
