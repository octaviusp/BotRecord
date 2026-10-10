import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts a SwiftUI surface drawn with Liquid Glass.
/// It never steals focus from the app being recorded.
final class FloatingPanel: NSPanel {
    var onCancel: (() -> Void)?
    private let acceptsKeyFocus: Bool

    init<Content: View>(level: NSWindow.Level, acceptsKeyFocus: Bool = false, @ViewBuilder content: () -> Content) {
        self.acceptsKeyFocus = acceptsKeyFocus
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: content())
        contentView = hostingView
        setContentSize(hostingView.fittingSize)
    }

    override var canBecomeKey: Bool { acceptsKeyFocus }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Fades in while sliding `distance` points toward its final spot.
    func present(at origin: NSPoint, slidingFrom distance: CGFloat = 10) {
        setFrameOrigin(NSPoint(x: origin.x, y: origin.y - distance))
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrameOrigin(origin)
        }
    }

    func dismissAnimated(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}
