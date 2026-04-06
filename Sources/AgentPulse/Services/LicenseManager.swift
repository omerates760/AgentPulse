// LicenseManager.swift — AgentPulse
// License validation, trial management, and edition tracking

import Foundation

enum LicenseError: LocalizedError {
    case invalidKey
    case networkError
    case activationLimit
    case disabled

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "Invalid license key"
        case .networkError: return "Network error, please try again"
        case .activationLimit: return "Activation limit reached. Deactivate another device first."
        case .disabled: return "This license key has been disabled"
        }
    }
}

class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published var isLicensed: Bool
    @Published var edition: String
    @Published var trialDaysRemaining: Int

    private let defaults = UserDefaults.standard
    private let trialDuration = 14 // days

    private init() {
        // Check stored license
        let licenseKey = defaults.string(forKey: "licenseKey") ?? ""
        let verified = defaults.bool(forKey: "licenseVerified")
        self.isLicensed = !licenseKey.isEmpty && verified
        self.edition = defaults.string(forKey: "licenseEdition") ?? ""

        // Calculate trial days
        let installDate = Self.installDate
        let daysSinceInstall = Calendar.current.dateComponents(
            [.day], from: installDate, to: Date()
        ).day ?? 0
        self.trialDaysRemaining = max(0, trialDuration - daysSinceInstall)
    }

    var isTrialExpired: Bool {
        !isLicensed && trialDaysRemaining <= 0
    }

    var isTrialActive: Bool {
        !isLicensed && trialDaysRemaining > 0
    }

    var hasAccess: Bool {
        isLicensed || isTrialActive
    }

    // MARK: - Activation

    func activate(key: String, completion: @escaping (Result<Void, LicenseError>) -> Void) {
        // Basic key format validation
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(.invalidKey))
            return
        }

        // Store the key locally (offline validation)
        // In a real app, this would call a license server
        defaults.set(trimmed, forKey: "licenseKey")
        defaults.set(true, forKey: "licenseVerified")

        // Determine edition based on key prefix
        let editionStr: String
        if trimmed.hasPrefix("VI-F") {
            editionStr = "FOUNDER"
        } else if trimmed.hasPrefix("VI-P") {
            editionStr = "PIONEER"
        } else if trimmed.hasPrefix("VI-E") {
            editionStr = "EXPLORER"
        } else if trimmed.hasPrefix("VI-V") {
            editionStr = "VOYAGER"
        } else {
            editionStr = "ISLANDER"
        }
        defaults.set(editionStr, forKey: "licenseEdition")

        DispatchQueue.main.async {
            self.isLicensed = true
            self.edition = editionStr
            completion(.success(()))
        }

        DiagnosticLogger.shared.log("License activated: \(editionStr)")
    }

    func deactivate() {
        defaults.removeObject(forKey: "licenseKey")
        defaults.removeObject(forKey: "licenseVerified")
        defaults.removeObject(forKey: "licenseEdition")

        DispatchQueue.main.async {
            self.isLicensed = false
            self.edition = ""
        }

        DiagnosticLogger.shared.log("License deactivated")
    }

    // MARK: - Install Date

    private static var installDate: Date {
        let key = "analyticsInstallDate"
        if let date = UserDefaults.standard.object(forKey: key) as? Date {
            return date
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: key)
        return now
    }
}
