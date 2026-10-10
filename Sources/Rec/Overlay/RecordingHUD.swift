import AppKit
import SwiftUI

/// Floating recording controls at the bottom of the target's display, plus the area outline for area captures.
@MainActor
final class RecordingHUD: RecordingHUDPresenting {
    /// Spare width on both sides so the capsule can grow when the timer passes an hour without resizing the panel.
    private static let timerGrowthSlack: CGFloat = 40
    private static let bottomMargin: CGFloat = 20

    private var panel: OverlayPanel?
    private var outline: RecordingAreaOutline?
    private var model: RecordingHUDModel?

    init() {}

    func show(for target: CaptureTarget, actions: RecordingHUDActions) {
        dismiss()
        guard let screen = ScreenSpace.screen(forDisplayID: target.displayID) ?? NSScreen.main else { return }

        if let area = target.sourceRect {
            outline = RecordingAreaOutline(areaFrame: ScreenSpace.appKitRect(fromCaptureRect: area, on: screen))
        }

        let model = RecordingHUDModel(actions: actions)
        let host = NSHostingView(rootView: RecordingHUDView(model: model))
        var size = host.fittingSize
        size.width += Self.timerGrowthSlack
        host.frame = CGRect(origin: .zero, size: size)

        let visible = screen.visibleFrame
        let frame = CGRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + Self.bottomMargin - OverlayMetrics.shadowInset,
            width: size.width,
            height: size.height
        )
        let panel = OverlayPanel(frame: frame, level: .statusBar, acceptsKeyboard: false)
        panel.isMovableByWindowBackground = true
        panel.contentView = host
        panel.orderFrontRegardless()

        self.model = model
        self.panel = panel
    }

    func update(elapsed: TimeInterval, isPaused: Bool) {
        guard let model else { return }
        let seconds = max(0, Int(elapsed))
        if model.elapsedSeconds != seconds { model.elapsedSeconds = seconds }
        if model.isPaused != isPaused { model.isPaused = isPaused }
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        outline?.close()
        outline = nil
        model = nil
    }
}
