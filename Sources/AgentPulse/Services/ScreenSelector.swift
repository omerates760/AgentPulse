// ScreenSelector.swift — AgentPulse
// Detects the notch screen and provides geometry for panel placement

import Foundation
import AppKit

class ScreenSelector {

    enum ScreenMode: String {
        case auto = "auto"
        case builtIn = "builtIn"
        case main = "main"
    }

    static var currentMode: ScreenMode {
        let raw = UserDefaults.standard.string(forKey: "agentPulse.screen.mode") ?? "auto"
        return ScreenMode(rawValue: raw) ?? .auto
    }

    // MARK: - Notch Screen Selection

    static func notchScreen() -> NSScreen {
        switch currentMode {
        case .builtIn:
            return builtInScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        case .main:
            return NSScreen.main ?? NSScreen.screens[0]
        case .auto:
            // Prefer screen with notch, fallback to built-in, then main
            if let notch = screenWithNotch() {
                return notch
            }
            if let builtIn = builtInScreen() {
                return builtIn
            }
            return NSScreen.main ?? NSScreen.screens[0]
        }
    }

    // MARK: - Notch Rect

    static func notchRect(for screen: NSScreen) -> CGRect {
        let frame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = frame.maxY - visibleFrame.maxY
        let width = notchWidth(for: screen)
        let centerX = frame.midX - width / 2.0

        return CGRect(
            x: centerX,
            y: frame.maxY - menuBarHeight,
            width: width,
            height: menuBarHeight
        )
    }

    // MARK: - Built-in Display Detection

    static func isBuiltInDisplay(_ screen: NSScreen) -> Bool {
        let description = screen.deviceDescription
        guard let screenNumber = description[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(screenNumber) != 0
    }

    // MARK: - Notch Width

    static var notchWidth: CGFloat {
        return notchWidth(for: notchScreen())
    }

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if hasNotch(screen) {
            return 200
        }
        return 180
    }

    // MARK: - Private Helpers

    static func screenWithNotch() -> NSScreen? {
        for screen in NSScreen.screens {
            if hasNotch(screen) {
                return screen
            }
        }
        return nil
    }

    private static func hasNotch(_ screen: NSScreen) -> Bool {
        // Detect notch by checking if the built-in display has a taller menu bar area
        // (notch screens have ~38pt vs ~24pt for non-notch)
        if isBuiltInDisplay(screen) {
            let frame = screen.frame
            let visibleFrame = screen.visibleFrame
            let menuBarHeight = frame.maxY - visibleFrame.maxY
            // Notch screens have a taller menu bar area (~38pt vs ~24pt)
            if menuBarHeight > 30 {
                return true
            }
        }
        return false
    }

    private static func builtInScreen() -> NSScreen? {
        return NSScreen.screens.first(where: { isBuiltInDisplay($0) })
    }
}
