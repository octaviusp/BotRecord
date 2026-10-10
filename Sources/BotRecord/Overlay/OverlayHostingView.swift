import AppKit
import SwiftUI

/// Hosting view that lets clicks fall through its transparent padding (glass shadows) to the view below.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    private let hitInset: CGFloat?

    /// - Parameter hitInset: padding around the visible content that ignores clicks; nil makes the whole view click-through.
    init(rootView: Content, hitInset: CGFloat?) {
        self.hitInset = hitInset
        super.init(rootView: rootView)
    }

    required init(rootView: Content) {
        hitInset = nil
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitInset else { return nil }
        let local = convert(point, from: superview)
        return bounds.insetBy(dx: hitInset, dy: hitInset).contains(local) ? super.hitTest(point) : nil
    }
}
