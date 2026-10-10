import CoreGraphics

enum SelectionPhase { case idle, drawing, adjusting }

enum SelectionCursor: Equatable { case crosshair, resize(ResizeHandle), move }

enum SelectionPointerUpResult { case none, pickedDisplay }

/// Selection state machine for ONE screen, in that screen's local AppKit coordinates (origin bottom-left).
/// Pure value logic: the canvas feeds it pointer events and renders whatever state comes out.
struct SelectionEngine {
    private enum Hit: Equatable { case handle(ResizeHandle), inside, outside }

    private enum Interaction {
        case drawing(anchor: CGPoint, clickedWindow: CGRect?, isDragging: Bool)
        case resizing(handle: ResizeHandle, start: CGRect, grabOffset: CGSize)
        case moving(start: CGRect, grab: CGPoint)
    }

    /// Movement under this distance is a click, not a drag.
    private static let dragThreshold: CGFloat = 4

    let bounds: CGRect
    let scale: CGFloat
    /// With several displays, clicking empty desktop records that display in full.
    let canPickDisplay: Bool

    private let editor: RectEditor
    private var snapper: SnapEngine
    private var windowFrames: [CGRect] = []
    private var hit: Hit = .outside
    private var interaction: Interaction?
    private var isShiftDown = false

    private(set) var phase: SelectionPhase = .idle
    private(set) var rect: CGRect = .zero
    private(set) var aspect: AspectPreset = .free
    private(set) var pointer: CGPoint?
    private(set) var hoveredWindow: CGRect?
    private(set) var guides: [SnapGuide] = []

    init(size: CGSize, scale: CGFloat, canPickDisplay: Bool) {
        bounds = CGRect(origin: .zero, size: size)
        self.scale = scale
        self.canPickDisplay = canPickDisplay
        editor = RectEditor(bounds: bounds)
        snapper = SnapEngine(bounds: bounds, windowFrames: [])
    }

    // MARK: Derived state

    var pixelSize: (width: Int, height: Int) {
        (Int((rect.width * scale).rounded()), Int((rect.height * scale).rounded()))
    }

    var isBelowMinimum: Bool {
        let size = pixelSize
        return size.width < SelectionLimits.minimumPixelSize.width || size.height < SelectionLimits.minimumPixelSize.height
    }

    var canRecord: Bool { phase == .adjusting && !isBelowMinimum }

    var isMoving: Bool {
        if case .moving = interaction { return true }
        return false
    }

    /// True while a drag is visibly changing the rect (the toolbar steps aside meanwhile).
    var isEditing: Bool {
        switch interaction {
        case .resizing, .moving: true
        case let .drawing(_, _, isDragging): isDragging
        case nil: false
        }
    }

    var isRatioLocked: Bool {
        if aspect.ratio != nil { return true }
        return isShiftDown && isEditing && !isMoving
    }

    var isHoveringDisplay: Bool {
        phase == .idle && canPickDisplay && pointer != nil && hoveredWindow == nil
    }

    /// Handle to draw big and blue: the one being dragged, or the one under the pointer.
    var emphasizedHandle: ResizeHandle? {
        if case let .resizing(handle, _, _) = interaction { return handle }
        if interaction == nil, case let .handle(handle) = hit { return handle }
        return nil
    }

    var cursor: SelectionCursor {
        switch interaction {
        case let .resizing(handle, _, _): return .resize(handle)
        case .moving: return .move
        case .drawing: return .crosshair
        case nil:
            switch hit {
            case let .handle(handle): return .resize(handle)
            case .inside: return .move
            case .outside: return .crosshair
            }
        }
    }

    /// Selected area in the display's top-left-origin points, the space `CaptureTarget.sourceRect` uses.
    var captureRect: CGRect {
        ScreenSpace.flippedVertically(rect, within: bounds.height)
    }

    // MARK: Input

    mutating func setWindowFrames(_ frames: [CGRect]) {
        windowFrames = frames.map { $0.intersection(bounds) }.filter { !$0.isNull && !$0.isEmpty }
        snapper = SnapEngine(bounds: bounds, windowFrames: windowFrames)
        if interaction == nil { refreshHover() }
    }

    mutating func pointerMoved(to point: CGPoint) {
        pointer = point
        if interaction == nil { refreshHover() }
    }

    mutating func pointerLeft() {
        pointer = nil
        if interaction == nil { refreshHover() }
    }

    mutating func pointerDown(at point: CGPoint, shiftDown: Bool) {
        isShiftDown = shiftDown
        pointer = point
        refreshHover()
        switch hit {
        case let .handle(handle):
            let grabOffset = CGSize(width: handle.point(in: rect).x - point.x, height: handle.point(in: rect).y - point.y)
            interaction = .resizing(handle: handle, start: rect, grabOffset: grabOffset)
        case .inside:
            interaction = .moving(start: rect, grab: point)
        case .outside:
            interaction = .drawing(anchor: editor.clamp(point), clickedWindow: hoveredWindow, isDragging: false)
        }
    }

    mutating func pointerDragged(to point: CGPoint, shiftDown: Bool) {
        isShiftDown = shiftDown
        pointer = point
        applyInteraction()
    }

    mutating func modifiersChanged(shiftDown: Bool) {
        isShiftDown = shiftDown
        if interaction != nil { applyInteraction() }
    }

    mutating func pointerUp() -> SelectionPointerUpResult {
        var result = SelectionPointerUpResult.none
        switch interaction {
        case let .drawing(_, clickedWindow, isDragging):
            if isDragging {
                commitRect()
            } else if let clickedWindow {
                rect = clickedWindow
                commitRect()
            } else if phase == .idle, canPickDisplay {
                result = .pickedDisplay
            }
        case .resizing, .moving:
            commitRect()
        case nil:
            break
        }
        interaction = nil
        guides = []
        refreshHover()
        return result
    }

    mutating func nudge(dx: CGFloat, dy: CGFloat) {
        guard phase == .adjusting, interaction == nil else { return }
        rect = editor.moved(rect, by: CGSize(width: dx, height: dy))
        refreshHover()
    }

    /// Picks an aspect preset; an existing selection reshapes around its center.
    mutating func chooseAspect(_ preset: AspectPreset) {
        aspect = preset
        guard phase == .adjusting, let ratio = preset.ratio else { return }
        rect = editor.pixelAligned(editor.reshaped(rect, toRatio: ratio), scale: scale)
        refreshHover()
    }

    mutating func reset() {
        phase = .idle
        rect = .zero
        interaction = nil
        guides = []
        refreshHover()
    }

    // MARK: Private

    private mutating func applyInteraction() {
        guard let pointer else { return }
        switch interaction {
        case let .drawing(anchor, clickedWindow, isDragging):
            if !isDragging {
                guard hypot(pointer.x - anchor.x, pointer.y - anchor.y) > Self.dragThreshold else { return }
                interaction = .drawing(anchor: anchor, clickedWindow: clickedWindow, isDragging: true)
                phase = .drawing
                hoveredWindow = nil
            }
            applyDrawing(anchor: anchor, to: pointer)
        case let .resizing(handle, start, grabOffset):
            applyResize(handle: handle, start: start, grabOffset: grabOffset, pointer: pointer)
        case let .moving(start, grab):
            let moved = editor.moved(start, by: CGSize(width: pointer.x - grab.x, height: pointer.y - grab.y))
            let snapped = snapper.snapMove(moved)
            rect = editor.clamped(snapped.rect)
            guides = snapped.guides
        case nil:
            break
        }
    }

    private mutating func applyDrawing(anchor: CGPoint, to pointer: CGPoint) {
        // Shift while drawing squares the rect; a chosen preset always wins.
        let ratio = aspect.ratio ?? (isShiftDown ? 1 : nil)
        var target = editor.clamp(pointer)
        guides = []
        if ratio == nil {
            let snapped = snapper.snap(target, snapX: true, snapY: true)
            target = snapped.point
            guides = snapped.guides
        }
        rect = editor.rect(anchor: anchor, to: target, ratio: ratio)
    }

    private mutating func applyResize(handle: ResizeHandle, start: CGRect, grabOffset: CGSize, pointer: CGPoint) {
        // Shift locks the shape the rect had when the drag began.
        let lockedRatio = start.height > 0 ? start.width / start.height : 1
        let ratio = aspect.ratio ?? (isShiftDown ? lockedRatio : nil)
        var target = editor.clamp(CGPoint(x: pointer.x + grabOffset.width, y: pointer.y + grabOffset.height))
        guides = []
        if ratio == nil {
            let snapped = snapper.snap(
                target,
                snapX: handle.movesMinX || handle.movesMaxX,
                snapY: handle.movesMinY || handle.movesMaxY
            )
            target = snapped.point
            guides = snapped.guides
        }
        rect = editor.resized(start, handle: handle, to: target, ratio: ratio)
    }

    private mutating func commitRect() {
        rect = editor.pixelAligned(rect, scale: scale)
        phase = .adjusting
    }

    private mutating func refreshHover() {
        guard let pointer else {
            hoveredWindow = nil
            hit = .outside
            return
        }
        switch phase {
        case .idle:
            hoveredWindow = windowFrames.first { $0.contains(pointer) }
            hit = .outside
        case .adjusting:
            hoveredWindow = nil
            hit = hitTest(pointer)
        case .drawing:
            hoveredWindow = nil
            hit = .outside
        }
    }

    private func hitTest(_ point: CGPoint) -> Hit {
        // Shrinks on tiny rects so handles never swallow the whole interior.
        let handleRadius = max(4, min(10, min(rect.width, rect.height) / 3))
        for handle in ResizeHandle.corners + ResizeHandle.edges
            where hypot(point.x - handle.point(in: rect).x, point.y - handle.point(in: rect).y) <= handleRadius {
            return .handle(handle)
        }
        let band = max(3, min(6, min(rect.width, rect.height) / 4))
        if (rect.minX - band ... rect.maxX + band).contains(point.x) {
            if abs(point.y - rect.maxY) <= band { return .handle(.top) }
            if abs(point.y - rect.minY) <= band { return .handle(.bottom) }
        }
        if (rect.minY - band ... rect.maxY + band).contains(point.y) {
            if abs(point.x - rect.minX) <= band { return .handle(.left) }
            if abs(point.x - rect.maxX) <= band { return .handle(.right) }
        }
        return rect.contains(point) ? .inside : .outside
    }
}
