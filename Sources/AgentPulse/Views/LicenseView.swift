// LicenseView.swift — AgentPulse
// License activation and management UI

import SwiftUI
import AppKit

// MARK: - License Window Controller

class LicenseWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 340),
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

        let view = NSHostingView(rootView: LicenseView(onClose: { [weak self] in
            self?.close()
        }))
        window.contentView = view
    }

    func showLicense() {
        window?.makeKeyAndOrderFront(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - License View

struct LicenseView: View {
    let onClose: () -> Void
    @State private var licenseKey = ""
    @State private var isActivating = false
    @State private var errorMessage: String?
    @State private var isLicensed = LicenseManager.shared.isLicensed

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                Image(systemName: isLicensed ? "checkmark.seal.fill" : "key.fill")
                    .font(.system(size: 36))
                    .foregroundColor(isLicensed ? .green : .orange)

                Text(isLicensed ? "License Active" : "Activate AgentPulse")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                if isLicensed {
                    activatedContent
                } else {
                    activateContent
                }
            }
            .padding(30)
        }
        .frame(width: 400, height: 340)
    }

    // MARK: - Activated State

    private var activatedContent: some View {
        VStack(spacing: 16) {
            Text("Thank you for supporting AgentPulse!")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))

            // Edition badge
            let edition = LicenseManager.shared.edition
            if !edition.isEmpty {
                Text(edition.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(6)
            }

            Spacer()

            Button(action: {
                LicenseManager.shared.deactivate()
                isLicensed = false
            }) {
                Text("Deactivate License")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Activate State

    private var activateContent: some View {
        VStack(spacing: 16) {
            Text("Enter the license key from your purchase confirmation email:")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            TextField("Enter license key", text: $licenseKey)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
                .disabled(isActivating)

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }

            Button(action: activate) {
                HStack {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                    Text(isActivating ? "Activating..." : "Activate")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.cyan)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(licenseKey.isEmpty || isActivating)

            // Trial info
            let daysLeft = LicenseManager.shared.trialDaysRemaining
            if daysLeft > 0 {
                Text("Trial (\(daysLeft) days left)")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            } else {
                Text("Trial ended")
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.6))
            }
        }
    }

    private func activate() {
        isActivating = true
        errorMessage = nil

        LicenseManager.shared.activate(key: licenseKey) { result in
            DispatchQueue.main.async {
                isActivating = false
                switch result {
                case .success:
                    isLicensed = true
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
