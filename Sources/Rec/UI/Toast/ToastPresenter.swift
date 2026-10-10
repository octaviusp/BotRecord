import AppKit

/// Owns the two toast panels: "saved" bottom-right, "failure" top-right.
@MainActor
final class ToastPresenter: RecordingOutcomePresenting {
    private var savedPanel: FloatingPanel?
    private var savedModel: SavedToastModel?
    private var failurePanel: FloatingPanel?
    private var failureDismissHandler: (@MainActor () -> Void)?

    private static let edgeMargin: CGFloat = 16

    func presentSaved(_ recording: SavedRecording) {
        dismissSaved()
        let model = SavedToastModel(recording: recording)
        model.onDismiss = { [weak self] in self?.dismissSaved() }
        let panel = FloatingPanel(level: .statusBar) { SavedToastView(model: model) }
        savedModel = model
        savedPanel = panel
        panel.present(at: origin(for: panel.frame.size, atTop: false))
        model.startAutoDismiss()
    }

    func presentFailure(_ failure: FailurePresentation, onDismiss: @escaping @MainActor () -> Void) {
        dismissFailure(notifying: false)
        let model = FailureToastModel(failure: failure)
        model.onDismiss = { [weak self] in self?.dismissFailure() }
        let panel = FloatingPanel(level: .statusBar) { FailureToastView(model: model) }
        failurePanel = panel
        failureDismissHandler = onDismiss
        panel.present(at: origin(for: panel.frame.size, atTop: true))
    }

    func dismissAll() {
        dismissSaved()
        dismissFailure()
    }

    private func dismissSaved() {
        savedModel?.stopAutoDismiss()
        savedModel = nil
        savedPanel?.dismissAnimated()
        savedPanel = nil
    }

    /// `notifying: false` when a newer failure replaces this one: the coordinator must stay in `.failed`.
    private func dismissFailure(notifying: Bool = true) {
        failurePanel?.dismissAnimated()
        failurePanel = nil
        let handler = failureDismissHandler
        failureDismissHandler = nil
        if notifying { handler?() }
    }

    private func origin(for size: NSSize, atTop: Bool) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let x = visible.maxX - size.width - Self.edgeMargin
        let y = atTop ? visible.maxY - size.height - Self.edgeMargin / 2 : visible.minY + Self.edgeMargin
        return NSPoint(x: x, y: y)
    }
}
