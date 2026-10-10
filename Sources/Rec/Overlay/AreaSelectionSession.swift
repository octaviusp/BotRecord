import AppKit

/// One run of the area picker: owns an overlay window per display and resolves to a `CaptureTarget`.
@MainActor
final class AreaSelectionSession: SelectionCanvasDelegate {
    private let request: AreaSelectionRequest
    private let toolbarModel: SelectionToolbarModel
    private var panels: [OverlayPanel] = []
    private var canvases: [SelectionCanvasView] = []
    private var continuation: CheckedContinuation<CaptureTarget?, Never>?
    private var windowLoading: Task<Void, Never>?

    init(request: AreaSelectionRequest) {
        self.request = request
        toolbarModel = SelectionToolbarModel(qualityBadge: request.qualityBadge)
    }

    func run() async -> CaptureTarget? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    // MARK: Presentation

    private func present() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(with: nil)
            return
        }
        toolbarModel.onSelectAspect = { [weak self] preset in self?.chooseAspect(preset) }
        toolbarModel.onCancel = { [weak self] in self?.finish(with: nil) }
        toolbarModel.onRecord = { [weak self] in self?.confirmSelection() }

        let detail = "Click to record · \(request.qualityBadge)"
        for screen in screens {
            let canvas = SelectionCanvasView(
                screen: screen,
                toolbarModel: toolbarModel,
                displayDetail: detail,
                canPickDisplay: screens.count > 1
            )
            canvas.delegate = self
            let panel = OverlayPanel(frame: screen.frame, level: .screenSaver, acceptsKeyboard: true)
            panel.acceptsMouseMovedEvents = true
            panel.contentView = canvas
            canvases.append(canvas)
            panels.append(panel)
        }

        let mouse = NSEvent.mouseLocation
        let keyIndex = screens.firstIndex { $0.frame.contains(mouse) } ?? 0
        NSApp.activate()
        for panel in panels { panel.orderFrontRegardless() }
        panels[keyIndex].makeKeyAndOrderFront(nil)
        panels[keyIndex].makeFirstResponder(canvases[keyIndex])
        canvases.forEach { $0.seedPointer(atGlobal: mouse) }
        NSCursor.crosshair.set()

        windowLoading = Task { [weak self] in
            let frames = await WindowCatalog.loadVisibleWindowFrames()
            guard !Task.isCancelled else { return }
            self?.canvases.forEach { $0.setWindowFrames(frames) }
        }
    }

    private func finish(with target: CaptureTarget?) {
        guard let continuation else { return }
        self.continuation = nil
        windowLoading?.cancel()
        // Windows must be gone before the caller starts capturing.
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels = []
        canvases = []
        NSCursor.arrow.set()
        continuation.resume(returning: target)
    }

    // MARK: Actions

    private var activeCanvas: SelectionCanvasView? {
        canvases.first { $0.hasSelection }
    }

    private func chooseAspect(_ preset: AspectPreset) {
        canvases.forEach { $0.chooseAspect(preset) }
    }

    private func confirmSelection() {
        guard let canvas = activeCanvas, canvas.engine.canRecord else { return }
        finish(with: canvas.captureTarget)
    }

    // MARK: SelectionCanvasDelegate

    func canvasWillBeginInteraction(_ canvas: SelectionCanvasView) {
        for other in canvases where other !== canvas { other.resetSelection() }
        canvas.chooseAspect(toolbarModel.aspect)
    }

    func canvasPointerDidEnter(_ canvas: SelectionCanvasView) {
        guard let window = canvas.window, !window.isKeyWindow else { return }
        window.makeKey()
        window.makeFirstResponder(canvas)
    }

    func canvasDidPickDisplay(_ canvas: SelectionCanvasView) {
        finish(with: canvas.fullDisplayTarget)
    }

    func canvasDidRequestFullDisplay(_ canvas: SelectionCanvasView) {
        let mouse = NSEvent.mouseLocation
        let underCursor = canvases.first { $0.screen.frame.contains(mouse) } ?? canvas
        finish(with: underCursor.fullDisplayTarget)
    }

    func canvasDidRequestConfirm(_ canvas: SelectionCanvasView) {
        confirmSelection()
    }

    func canvasDidRequestCancel(_ canvas: SelectionCanvasView) {
        finish(with: nil)
    }
}
