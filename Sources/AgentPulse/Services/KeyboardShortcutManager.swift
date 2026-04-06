// KeyboardShortcutManager.swift — AgentPulse
// Global keyboard shortcut manager using Carbon Hot Key API

import Foundation
import AppKit
import Carbon

class KeyboardShortcutManager {
    static let shared = KeyboardShortcutManager()

    var onTogglePanel: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var modifierMonitor: Any?
    private var modifierPressTime: Date?

    // Modifier hold detection
    private let modifierHoldThreshold: TimeInterval = 0.5
    var onModifierHeld: (() -> Void)?
    var onModifierReleased: (() -> Void)?

    private init() {}

    // MARK: - Registration

    func register() {
        unregister()

        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKey()
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, selfPtr, &eventHandler)

        // Register Cmd+Shift+V as default hotkey
        // 'V' key code = 9
        let modifiers = modifierKeyCarbon()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5649424C), id: 1) // "AGPL"
        let keyCode: UInt32 = 9 // 'V'
        let combinedModifiers = UInt32(shiftKey) | modifiers

        RegisterEventHotKey(keyCode, combinedModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        // Start modifier hold detection
        startModifierMonitoring()

        DiagnosticLogger.shared.log("Keyboard shortcuts registered")
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        stopModifierMonitoring()
    }

    // MARK: - Modifier Key Config

    private func modifierKeyCarbon() -> UInt32 {
        let raw = UserDefaults.standard.string(forKey: "modifierKey") ?? "command"
        let option = ModifierKeyOption(rawValue: raw) ?? .command
        return option.carbonModifier
    }

    private func modifierKeyNSEvent() -> NSEvent.ModifierFlags {
        let raw = UserDefaults.standard.string(forKey: "modifierKey") ?? "command"
        let option = ModifierKeyOption(rawValue: raw) ?? .command
        return option.nsEventModifier
    }

    // MARK: - Modifier Hold Detection

    private func startModifierMonitoring() {
        let targetModifier = modifierKeyNSEvent()

        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }

            if event.modifierFlags.contains(targetModifier) {
                // Modifier pressed
                if self.modifierPressTime == nil {
                    self.modifierPressTime = Date()

                    DispatchQueue.main.asyncAfter(deadline: .now() + self.modifierHoldThreshold) { [weak self] in
                        guard let self = self, let pressTime = self.modifierPressTime else { return }
                        if Date().timeIntervalSince(pressTime) >= self.modifierHoldThreshold {
                            self.onModifierHeld?()
                        }
                    }
                }
            } else {
                // Modifier released
                self.modifierPressTime = nil
                self.onModifierReleased?()
            }
        }
    }

    private func stopModifierMonitoring() {
        if let monitor = modifierMonitor {
            NSEvent.removeMonitor(monitor)
            modifierMonitor = nil
        }
        modifierPressTime = nil
    }

    // MARK: - Hot Key Handler

    private func handleHotKey() {
        DispatchQueue.main.async { [weak self] in
            self?.onTogglePanel?()
        }
    }

    deinit {
        unregister()
    }
}
