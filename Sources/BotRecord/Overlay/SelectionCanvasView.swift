import AppKit
import QuartzCore

@MainActor
protocol SelectionCanvasDelegate: AnyObject {
    /// A pointer press is about to start on this canvas; other screens must drop their selection.
    func canvasWillBeginInteraction(_ canvas: SelectionCanvasView)
    func canvasPointerDidEnter(_ canvas: SelectionCanvasView)
    func canvasDidPickDisplay(_ canvas: SelectionCanvasView)
    func canvasDidRequestFullDisplay(_ canvas: SelectionCanvasView)
    func canvasDidRequestConfirm(_ canvas: SelectionCanvasView)
    func canvasDidRequestCancel(_ canvas: SelectionCanvasView)
}

/// Full-screen surface of the area picker for one display. Shapes are CALayers (GPU-composited path
/// updates keep dragging instant even on 5K); labels are tiny AppKit pills; glass chrome is SwiftUI.
@MainActor
final class SelectionCanvasView: NSView {
    private enum Metric {
        static let borderWidth: CGFloat = 1.5
        static let handleDiameter: CGFloat = 9
        static let emphasizedHandleDiameter: CGFloat = 15
        static let windowCornerRadius: CGFloat = 12
        static let labelGap: CGFloat = 6
        static let screenMargin: CGFloat = 4
        static let toolbarGap: CGFloat = 12
        static let hintTopMargin: CGFloat = 14
        static let pointerTagOffset: CGFloat = 16
        static let minimumThirdsSide: CGFloat = 90
        /// Almost-invisible fill: fully transparent window pixels let clicks through to the apps below.
        static let clickCatcherAlpha: CGFloat = 0.01
    }

    let screen: NSScreen
    weak var delegate: SelectionCanvasDelegate?
    private(set) var engine: SelectionEngine

    private let toolbarModel: SelectionToolbarModel

    private let scrimLayer = CAShapeLayer()
    private let clickCatcherLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let thirdsLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let edgeLayer = CAShapeLayer()
    private let guideLayer = CAShapeLayer()
    private let handleLayers: [ResizeHandle: CAShapeLayer]

    private let hintHost = OverlayHostingView(rootView: SelectionHintView(), hitInset: nil)
    private let toolbarHost: OverlayHostingView<SelectionToolbarView>
    private let displayCardHost: OverlayHostingView<SelectionDisplayCard>
    private let sizePill = SelectionPillView()
    private let pointerPill = SelectionPillView()
    private let windowPill = SelectionPillView()
    private let snapPill = SelectionPillView()

    init(screen: NSScreen, toolbarModel: SelectionToolbarModel, displayDetail: String, canPickDisplay: Bool) {
        self.screen = screen
        self.toolbarModel = toolbarModel
        engine = SelectionEngine(size: screen.frame.size, scale: screen.backingScaleFactor, canPickDisplay: canPickDisplay)
        handleLayers = Dictionary(uniqueKeysWithValues: ResizeHandle.allCases.map { ($0, CAShapeLayer()) })
        toolbarHost = OverlayHostingView(rootView: SelectionToolbarView(model: toolbarModel), hitInset: OverlayMetrics.shadowInset)
        displayCardHost = OverlayHostingView(
            rootView: SelectionDisplayCard(name: screen.localizedName, detail: displayDetail),
            hitInset: nil
        )
        super.init(frame: CGRect(origin: .zero, size: screen.frame.size))
        wantsLayer = true
        installShapeLayers()
        for host in [hintHost, displayCardHost, toolbarHost] as [NSView] {
            host.setFrameSize(host.fittingSize)
            addSubview(host)
        }
        for pill in [sizePill, pointerPill, windowPill, snapPill] { addSubview(pill) }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Session-facing API

    var hasSelection: Bool { engine.phase == .adjusting }

    var captureTarget: CaptureTarget {
        CaptureTarget(displayID: screen.displayID, sourceRect: engine.captureRect)
    }

    var fullDisplayTarget: CaptureTarget {
        CaptureTarget(displayID: screen.displayID, sourceRect: nil)
    }

    func setWindowFrames(_ globalFrames: [CGRect]) {
        let origin = screen.frame.origin
        engine.setWindowFrames(globalFrames.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) })
        render()
    }

    /// Feeds the current mouse position so hover state is right before the first mouse move.
    func seedPointer(atGlobal point: CGPoint) {
        guard screen.frame.contains(point) else { return }
        engine.pointerMoved(to: CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY))
        render()
    }

    func resetSelection() {
        engine.reset()
        render()
    }

    func chooseAspect(_ preset: AspectPreset) {
        engine.chooseAspect(preset)
        render()
    }

    // MARK: Events

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? screen.backingScaleFactor
        ([scrimLayer, clickCatcherLayer, highlightLayer, thirdsLayer, borderLayer, edgeLayer, guideLayer] + Array(handleLayers.values))
            .forEach { $0.contentsScale = scale }
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.canvasPointerDidEnter(self)
        track(event)
    }

    override func mouseExited(with event: NSEvent) {
        engine.pointerLeft()
        render()
    }

    override func mouseMoved(with event: NSEvent) { track(event) }

    override func cursorUpdate(with event: NSEvent) { applyCursor() }

    override func mouseDown(with event: NSEvent) {
        delegate?.canvasWillBeginInteraction(self)
        engine.pointerDown(at: localPoint(of: event), shiftDown: event.modifierFlags.contains(.shift))
        render()
        applyCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        engine.pointerDragged(to: localPoint(of: event), shiftDown: event.modifierFlags.contains(.shift))
        render()
        applyCursor()
    }

    override func mouseUp(with event: NSEvent) {
        let result = engine.pointerUp()
        render()
        applyCursor()
        if result == .pickedDisplay { delegate?.canvasDidPickDisplay(self) }
    }

    override func flagsChanged(with event: NSEvent) {
        engine.modifiersChanged(shiftDown: event.modifierFlags.contains(.shift))
        render()
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 53: delegate?.canvasDidRequestCancel(self)
        case 49: delegate?.canvasDidRequestFullDisplay(self)
        case 36, 76: delegate?.canvasDidRequestConfirm(self)
        case 123: nudge(dx: -step, dy: 0)
        case 124: nudge(dx: step, dy: 0)
        case 125: nudge(dx: 0, dy: -step)
        case 126: nudge(dx: 0, dy: step)
        default: break
        }
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        engine.nudge(dx: dx, dy: dy)
        render()
    }

    private func track(_ event: NSEvent) {
        engine.pointerMoved(to: localPoint(of: event))
        render()
        applyCursor()
    }

    private func localPoint(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func applyCursor() {
        let overToolbar = !toolbarHost.isHidden && engine.pointer.map { toolbarHost.frame.insetBy(dx: OverlayMetrics.shadowInset, dy: OverlayMetrics.shadowInset).contains($0) } == true
        (overToolbar ? NSCursor.arrow : SelectionCursors.cursor(for: engine.cursor)).set()
    }

    // MARK: Rendering

    private func installShapeLayers() {
        guard let root = layer else { return }
        scrimLayer.fillRule = .evenOdd
        scrimLayer.fillColor = NSColor(Theme.scrim).cgColor
        clickCatcherLayer.fillColor = NSColor.black.withAlphaComponent(Metric.clickCatcherAlpha).cgColor
        highlightLayer.fillColor = NSColor(Theme.accent).withAlphaComponent(0.14).cgColor
        highlightLayer.strokeColor = NSColor(Theme.accent).cgColor
        highlightLayer.lineWidth = 2.5
        thirdsLayer.strokeColor = NSColor.white.withAlphaComponent(0.35).cgColor
        thirdsLayer.lineWidth = 1
        borderLayer.fillColor = nil
        borderLayer.lineWidth = Metric.borderWidth
        edgeLayer.strokeColor = NSColor(Theme.accent).cgColor
        edgeLayer.lineWidth = 3
        guideLayer.strokeColor = NSColor(Theme.warning).cgColor
        guideLayer.lineWidth = 1
        // CAShapeLayer fills black by default; only the layers that should fill say so.
        for shape in [thirdsLayer, edgeLayer, guideLayer] { shape.fillColor = nil }
        let ordered = [scrimLayer, clickCatcherLayer, highlightLayer, thirdsLayer, borderLayer, edgeLayer, guideLayer]
            + ResizeHandle.allCases.compactMap { handleLayers[$0] }
        for shape in ordered {
            shape.frame = bounds
            root.addSublayer(shape)
        }
    }

    func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        renderShapes()
        renderLabels()
        renderChrome()
    }

    private func renderShapes() {
        let state = engine
        let showsSelection = state.phase != .idle
        let spotlight: (rect: CGRect, radius: CGFloat)? = if showsSelection {
            (state.rect, 0)
        } else if state.isHoveringDisplay {
            (bounds, 0)
        } else if let window = state.hoveredWindow {
            (window, Metric.windowCornerRadius)
        } else {
            nil
        }

        let scrimPath = CGMutablePath()
        scrimPath.addRect(bounds)
        if let spotlight { scrimPath.addPath(roundedPath(spotlight.rect, radius: spotlight.radius)) }
        scrimLayer.path = scrimPath
        clickCatcherLayer.path = spotlight.map { roundedPath($0.rect, radius: $0.radius) }

        let highlighted = state.phase == .idle ? spotlight : nil
        highlightLayer.isHidden = highlighted == nil
        if let highlighted {
            let inset = state.isHoveringDisplay ? highlightLayer.lineWidth / 2 : 0
            highlightLayer.path = roundedPath(highlighted.rect.insetBy(dx: inset, dy: inset), radius: highlighted.radius)
        }

        thirdsLayer.isHidden = !(showsSelection && min(state.rect.width, state.rect.height) >= Metric.minimumThirdsSide)
        if !thirdsLayer.isHidden {
            let path = CGMutablePath()
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                let x = state.rect.minX + state.rect.width * fraction
                let y = state.rect.minY + state.rect.height * fraction
                path.move(to: CGPoint(x: x, y: state.rect.minY)); path.addLine(to: CGPoint(x: x, y: state.rect.maxY))
                path.move(to: CGPoint(x: state.rect.minX, y: y)); path.addLine(to: CGPoint(x: state.rect.maxX, y: y))
            }
            thirdsLayer.path = path
        }

        borderLayer.isHidden = !showsSelection
        if showsSelection {
            borderLayer.path = CGPath(rect: state.rect, transform: nil)
            let isTooSmall = state.phase == .adjusting && state.isBelowMinimum
            borderLayer.strokeColor = (isTooSmall ? NSColor(Theme.record) : NSColor.white).cgColor
        }

        renderHandles(state)

        guideLayer.isHidden = state.guides.isEmpty
        let guidePath = CGMutablePath()
        for guide in state.guides {
            switch guide.axis {
            case .vertical:
                guidePath.move(to: CGPoint(x: guide.position, y: 0)); guidePath.addLine(to: CGPoint(x: guide.position, y: bounds.height))
            case .horizontal:
                guidePath.move(to: CGPoint(x: 0, y: guide.position)); guidePath.addLine(to: CGPoint(x: bounds.width, y: guide.position))
            }
        }
        guideLayer.path = guidePath
    }

    private func renderHandles(_ state: SelectionEngine) {
        let showsHandles = state.phase == .adjusting && !state.isMoving
        let emphasized = state.emphasizedHandle
        for (handle, shape) in handleLayers {
            shape.isHidden = !showsHandles
            guard showsHandles else { continue }
            let isEmphasized = handle == emphasized
            let diameter = isEmphasized ? Metric.emphasizedHandleDiameter : Metric.handleDiameter
            let ring: CGFloat = 2
            shape.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            shape.position = handle.point(in: state.rect)
            shape.path = CGPath(ellipseIn: shape.bounds.insetBy(dx: ring / 2, dy: ring / 2), transform: nil)
            shape.lineWidth = ring
            shape.fillColor = (isEmphasized ? NSColor(Theme.accent) : NSColor.white).cgColor
            shape.strokeColor = (isEmphasized ? NSColor.white : NSColor(Theme.accent)).cgColor
        }

        edgeLayer.isHidden = !(showsHandles && emphasized.map { !$0.isCorner } == true)
        if !edgeLayer.isHidden, let emphasized {
            let path = CGMutablePath()
            let (start, end) = edgeEndpoints(of: emphasized, in: state.rect)
            path.move(to: start)
            path.addLine(to: end)
            edgeLayer.path = path
        }
    }

    private func edgeEndpoints(of handle: ResizeHandle, in rect: CGRect) -> (CGPoint, CGPoint) {
        switch handle {
        case .top: (ResizeHandle.topLeft.point(in: rect), ResizeHandle.topRight.point(in: rect))
        case .bottom: (ResizeHandle.bottomLeft.point(in: rect), ResizeHandle.bottomRight.point(in: rect))
        case .left: (ResizeHandle.bottomLeft.point(in: rect), ResizeHandle.topLeft.point(in: rect))
        default: (ResizeHandle.bottomRight.point(in: rect), ResizeHandle.topRight.point(in: rect))
        }
    }

    private func renderLabels() {
        let state = engine
        renderSizePill(state)

        if state.phase == .idle, let pointer = state.pointer, !state.isHoveringDisplay {
            let x = Int(pointer.x.rounded())
            let y = Int((bounds.height - pointer.y).rounded())
            pointerPill.show([.init(text: "x \(x)  y \(y)")], style: .dark)
            pointerPill.setFrameOrigin(pointerTagOrigin(near: pointer, size: pointerPill.frame.size))
        } else {
            pointerPill.hide()
        }

        if state.phase == .idle, let window = state.hoveredWindow {
            windowPill.show([.init(text: "Click to select window")], symbol: "macwindow", style: .accent)
            var origin = CGPoint(x: window.minX + Metric.labelGap, y: window.minY - Metric.labelGap - windowPill.frame.height)
            if origin.y < Metric.screenMargin { origin.y = window.minY + Metric.labelGap }
            windowPill.setFrameOrigin(origin)
        } else {
            windowPill.hide()
        }

        if !state.guides.isEmpty, state.phase != .idle {
            snapPill.show([.init(text: "Snapped")], symbol: "scope", style: .warning)
            var origin = CGPoint(x: state.rect.maxX - snapPill.frame.width, y: state.rect.minY - Metric.labelGap - snapPill.frame.height)
            if origin.y < Metric.screenMargin { origin.y = state.rect.minY + Metric.labelGap }
            snapPill.setFrameOrigin(clampedHorizontally(origin, width: snapPill.frame.width))
        } else {
            snapPill.hide()
        }
    }

    private func renderSizePill(_ state: SelectionEngine) {
        guard state.phase == .drawing || state.phase == .adjusting else {
            sizePill.hide()
            return
        }
        let size = state.pixelSize
        if state.isMoving {
            let origin = state.captureRect.origin
            sizePill.show([.init(text: "x \(Int(origin.x.rounded()))  y \(Int(origin.y.rounded()))")], style: .dark)
        } else if state.phase == .adjusting, state.isBelowMinimum {
            let minimum = SelectionLimits.minimumPixelSize
            sizePill.show([.init(text: "Min \(minimum.width) × \(minimum.height)")], symbol: "exclamationmark.circle", style: .danger)
        } else {
            var segments = [SelectionPillView.Segment(text: "\(size.width) × \(size.height)")]
            if state.phase == .adjusting || state.isRatioLocked {
                let ratio = AspectNaming.name(forPixelWidth: size.width, height: size.height).map { " · \($0)" } ?? ""
                segments.append(.init(text: " px\(ratio)", isSecondary: true))
            }
            sizePill.show(segments, symbol: state.isRatioLocked ? "lock.fill" : nil, style: state.isRatioLocked ? .accent : .dark)
        }
        var origin = CGPoint(x: state.rect.minX, y: state.rect.maxY + Metric.labelGap)
        if origin.y + sizePill.frame.height > bounds.maxY - Metric.screenMargin {
            origin.y = state.rect.maxY - Metric.labelGap - sizePill.frame.height
        }
        sizePill.setFrameOrigin(clampedHorizontally(origin, width: sizePill.frame.width))
    }

    private func renderChrome() {
        let state = engine

        hintHost.isHidden = state.phase != .idle
        if !hintHost.isHidden {
            let visibleTop = screen.visibleFrame.maxY - screen.frame.minY
            hintHost.setFrameOrigin(CGPoint(
                x: (bounds.width - hintHost.frame.width) / 2,
                y: visibleTop - Metric.hintTopMargin - hintHost.frame.height + OverlayMetrics.shadowInset
            ))
        }

        displayCardHost.isHidden = !state.isHoveringDisplay
        displayCardHost.setFrameOrigin(CGPoint(
            x: (bounds.width - displayCardHost.frame.width) / 2,
            y: (bounds.height - displayCardHost.frame.height) / 2
        ))

        toolbarHost.isHidden = !(state.phase == .adjusting && !state.isEditing)
        if !toolbarHost.isHidden {
            toolbarModel.aspect = state.aspect
            toolbarModel.canRecord = state.canRecord
            toolbarHost.setFrameOrigin(toolbarOrigin(below: state.rect))
        }
    }

    // MARK: Layout helpers

    /// Toolbar goes under the area, above it when the screen bottom is too close, else inside the area.
    private func toolbarOrigin(below rect: CGRect) -> CGPoint {
        let inset = OverlayMetrics.shadowInset
        let visible = CGSize(width: toolbarHost.frame.width - 2 * inset, height: toolbarHost.frame.height - 2 * inset)
        let margin = Metric.screenMargin
        var bottom = rect.minY - Metric.toolbarGap - visible.height
        if bottom < screen.visibleFrame.minY - screen.frame.minY + margin {
            bottom = rect.maxY + Metric.toolbarGap
            if bottom + visible.height > bounds.maxY - margin {
                bottom = rect.minY + Metric.toolbarGap
            }
        }
        let left = min(max(rect.midX - visible.width / 2, margin), bounds.maxX - visible.width - margin)
        return CGPoint(x: left - inset, y: bottom - inset)
    }

    private func pointerTagOrigin(near pointer: CGPoint, size: CGSize) -> CGPoint {
        var origin = CGPoint(x: pointer.x + Metric.pointerTagOffset, y: pointer.y - Metric.pointerTagOffset - size.height)
        if origin.x + size.width > bounds.maxX - Metric.screenMargin { origin.x = pointer.x - Metric.pointerTagOffset - size.width }
        if origin.y < Metric.screenMargin { origin.y = pointer.y + Metric.pointerTagOffset }
        return origin
    }

    private func clampedHorizontally(_ origin: CGPoint, width: CGFloat) -> CGPoint {
        CGPoint(x: min(max(origin.x, Metric.screenMargin), bounds.maxX - width - Metric.screenMargin), y: origin.y)
    }

    private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let limited = min(radius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: limited, cornerHeight: limited, transform: nil)
    }
}
