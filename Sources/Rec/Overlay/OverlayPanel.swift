import AppKit

/// Borderless transparent panel shared by every overlay. Non-activating so showing it never steals focus
/// from the app being recorded, yet able to become key when it needs the keyboard (selection, countdown).
final class OverlayPanel: NSPanel {
    private let acceptsKeyboard: Bool

    init(frame: CGRect, level: NSWindow.Level, acceptsKeyboard: Bool) {
        self.acceptsKeyboard = acceptsKeyboard
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        // NSPanel hides on app deactivation by default, which would blank overlays whenever focus moves.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    /// AppKit would otherwise push full-screen panels below the menu bar and edge windows back on screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
