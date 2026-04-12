// NotchPanel.swift — AgentPulse
// Custom NSPanel subclass for the notch overlay

import AppKit
import SwiftUI
import Combine

final class NotchPanel: NSPanel {

    // MARK: - Constants

    private enum Layout {
        static let collapsedWidthIdle: CGFloat = 160
        static let collapsedWidthActive: CGFloat = 280
        static let collapsedHeight: CGFloat = 28
        static let expandedMinWidth: CGFloat = 500
        static let expandedMaxHeightRatio: CGFloat = 0.85
        static let collapsedCornerRadius: CGFloat = 16
        static let expandedCornerRadius: CGFloat = 20
    }

    // MARK: - Properties

    private(set) var isExpanded: Bool = false
    var hasActiveSessions: Bool = false
    var onHoverChanged: ((Bool) -> Void)?

    private let backgroundView: NSVisualEffectView = {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = Layout.collapsedCornerRadius
        view.layer?.masksToBounds = true
        return view
    }()

    // Glow border layer
    private let glowLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.type = .conic
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 0.5, y: 0)
        layer.cornerRadius = Layout.collapsedCornerRadius
        layer.opacity = 0
        return layer
    }()

    private var glowTimer: Timer?
    private var glowAngle: CGFloat = 0
    private var hoverTrackingArea: NSTrackingArea?

    // MARK: - Overrides

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Init

    init() {
        let frame = NSRect(x: 0, y: 0, width: Layout.collapsedWidthIdle, height: Layout.collapsedHeight)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        configurePanel()
        configureBackground()
        rebuildTrackingArea()
    }

    private func configurePanel() {
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    private func configureBackground() {
        guard let cv = contentView else { return }
        cv.wantsLayer = true

        // Glow layer (behind background)
        glowLayer.frame = cv.bounds.insetBy(dx: -2, dy: -2)
        glowLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        cv.layer?.addSublayer(glowLayer)

        // Background view
        backgroundView.frame = cv.bounds
        backgroundView.autoresizingMask = [.width, .height]
        cv.addSubview(backgroundView, positioned: .below, relativeTo: nil)
    }

    // MARK: - Glow Effect

    func updateGlow(color: NSColor, intensity: Float) {
        let cgColor = color.cgColor
        let clear = NSColor.clear.cgColor
        glowLayer.colors = [cgColor, clear, clear, cgColor, clear, clear, cgColor]

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.5
            glowLayer.opacity = intensity
        }

        if intensity > 0 && glowTimer == nil {
            startGlowRotation()
        } else if intensity == 0 {
            stopGlowRotation()
        }
    }

    private func startGlowRotation() {
        glowTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.glowAngle += 0.02
            let rotation = CATransform3DMakeRotation(self.glowAngle, 0, 0, 1)
            self.glowLayer.transform = rotation
        }
    }

    private func stopGlowRotation() {
        glowTimer?.invalidate()
        glowTimer = nil
    }

    // MARK: - Tracking Areas

    private func rebuildTrackingArea() {
        guard let cv = contentView else { return }
        if let existing = hoverTrackingArea { cv.removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: cv.bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        cv.addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChanged?(false)
    }

    // MARK: - Expand / Collapse

    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        animateToCurrentState()
    }

    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        animateToCurrentState()
    }

    private var targetSize: NSSize {
        if !isExpanded {
            let w = hasActiveSessions ? Layout.collapsedWidthActive : Layout.collapsedWidthIdle
            return NSSize(width: w, height: Layout.collapsedHeight)
        }
        let scr = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let w = max(Layout.expandedMinWidth, scr.frame.width * 0.5)
        let h = scr.frame.height * Layout.expandedMaxHeightRatio
        return NSSize(width: w, height: h)
    }

    private var targetCornerRadius: CGFloat {
        isExpanded ? Layout.expandedCornerRadius : Layout.collapsedCornerRadius
    }

    private func animateToCurrentState() {
        guard let screen = screen ?? NSScreen.main else { return }
        let newFrame = frameForSize(targetSize, on: screen)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(newFrame, display: true)
            self.backgroundView.layer?.cornerRadius = targetCornerRadius
            self.glowLayer.cornerRadius = targetCornerRadius
        } completionHandler: {
            self.rebuildTrackingArea()
        }
    }

    // MARK: - Positioning

    func positionOnScreen(_ screen: NSScreen) {
        let newFrame = frameForSize(targetSize, on: screen)
        setFrame(newFrame, display: true)
        rebuildTrackingArea()
    }

    private func frameForSize(_ size: NSSize, on screen: NSScreen) -> NSRect {
        let sf = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = sf.maxY - visibleFrame.maxY
        let x = sf.midX - (size.width / 2)
        let y: CGFloat
        if isExpanded {
            // Expanded: starts from menu bar bottom, grows downward
            y = sf.maxY - menuBarHeight - size.height
        } else {
            // Collapsed: sits just below the notch, touching menu bar bottom edge
            y = sf.maxY - menuBarHeight - size.height + 2
        }
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    // MARK: - Content

    func setHostingView(_ hostingView: NSView) {
        guard let cv = contentView else { return }
        for sub in cv.subviews where sub !== backgroundView { sub.removeFromSuperview() }
        hostingView.frame = cv.bounds
        hostingView.autoresizingMask = [.width, .height]
        cv.addSubview(hostingView)
    }

    /// Update collapsed pill width based on session activity
    func updateCollapsedState(hasActive: Bool) {
        let changed = hasActiveSessions != hasActive
        hasActiveSessions = hasActive
        if !isExpanded && changed {
            guard let screen = screen ?? NSScreen.main else { return }
            let newFrame = frameForSize(targetSize, on: screen)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.9, 0.3, 1.0)
                ctx.allowsImplicitAnimation = true
                self.animator().setFrame(newFrame, display: true)
            } completionHandler: { self.rebuildTrackingArea() }
        }
    }

    func updateExpandedSize(height: CGFloat) {
        guard isExpanded, let screen = screen ?? NSScreen.main else { return }
        let h = max(Layout.collapsedHeight, min(height, screen.frame.height * Layout.expandedMaxHeightRatio))
        let w = max(Layout.expandedMinWidth, screen.frame.width * 0.5)
        let newFrame = frameForSize(NSSize(width: w, height: h), on: screen)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            self.animator().setFrame(newFrame, display: true)
        } completionHandler: { self.rebuildTrackingArea() }
    }

    deinit {
        stopGlowRotation()
    }
}

// MARK: - NotchHostingView

/// Custom NSHostingView subclass that fixes common NSPanel + SwiftUI issues:
/// 1. First-click not firing SwiftUI actions (panel not key)
/// 2. NSHostingView constraint-update re-entrancy crash
final class NotchHostingView<Content: View>: NSHostingView<Content> {

    private var isUpdatingConstraints = false
    private var isUpdatingLayout = false

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateConstraints() {
        if isUpdatingConstraints { return }
        isUpdatingConstraints = true
        super.updateConstraints()
        isUpdatingConstraints = false
    }

    override func layout() {
        if isUpdatingLayout { return }
        isUpdatingLayout = true
        super.layout()
        isUpdatingLayout = false
    }
}
