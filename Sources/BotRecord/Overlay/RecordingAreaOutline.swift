import AppKit

/// Thin red frame just outside the recorded area. Click-through, so it never blocks the app being recorded.
@MainActor
final class RecordingAreaOutline {
    static let thickness: CGFloat = 2

    private let panel: OverlayPanel

    /// - Parameter areaFrame: the recorded area in AppKit global coordinates.
    init(areaFrame: CGRect) {
        let outer = areaFrame.insetBy(dx: -Self.thickness, dy: -Self.thickness)
        panel = OverlayPanel(frame: outer, level: .statusBar, acceptsKeyboard: false)
        panel.ignoresMouseEvents = true

        // The border is drawn inside the layer's bounds, i.e. in the margin around the area.
        let view = NSView(frame: CGRect(origin: .zero, size: outer.size))
        view.wantsLayer = true
        view.layer?.borderWidth = Self.thickness
        view.layer?.borderColor = NSColor(Theme.record).cgColor
        panel.contentView = view
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}
