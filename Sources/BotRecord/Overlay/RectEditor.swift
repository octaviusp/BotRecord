import CoreGraphics

/// Pure rectangle math for the selection: every result stays inside `bounds`.
/// Coordinates are AppKit's (y grows upward).
struct RectEditor {
    private static let minimumSide: CGFloat = 1

    let bounds: CGRect

    func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// Shifts a rect back inside the bounds, shrinking it only when it is larger than them.
    func clamped(_ rect: CGRect) -> CGRect {
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        return CGRect(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }

    /// Rect spanned by a fixed corner and a moving point; `ratio` (width / height) keeps the shape,
    /// growing toward the point as far as the bounds allow.
    func rect(anchor: CGPoint, to point: CGPoint, ratio: CGFloat?) -> CGRect {
        let target = clamp(point)
        let dx = target.x - anchor.x
        let dy = target.y - anchor.y
        guard let ratio else {
            return CGRect(x: min(anchor.x, target.x), y: min(anchor.y, target.y), width: abs(dx), height: abs(dy))
        }
        let signX: CGFloat = dx < 0 ? -1 : 1
        let signY: CGFloat = dy < 0 ? -1 : 1
        let availableWidth = signX > 0 ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let availableHeight = signY > 0 ? bounds.maxY - anchor.y : anchor.y - bounds.minY
        let width = min(max(abs(dx), abs(dy) * ratio), availableWidth, availableHeight * ratio)
        let height = width / ratio
        let farX = anchor.x + signX * width
        let farY = anchor.y + signY * height
        return CGRect(x: min(anchor.x, farX), y: min(anchor.y, farY), width: width, height: height)
    }

    func resized(_ start: CGRect, handle: ResizeHandle, to point: CGPoint, ratio: CGFloat?) -> CGRect {
        if handle.isCorner {
            return rect(anchor: handle.opposite.point(in: start), to: point, ratio: ratio)
        }
        let target = clamp(point)
        guard let ratio else { return freeEdgeResize(start, handle: handle, target: target) }
        return ratioEdgeResize(start, handle: handle, target: target, ratio: ratio)
    }

    func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        clamped(rect.offsetBy(dx: delta.width, dy: delta.height))
    }

    /// Reshapes around the center to a new ratio while keeping roughly the same area.
    func reshaped(_ rect: CGRect, toRatio ratio: CGFloat) -> CGRect {
        var width = (rect.width * rect.height * ratio).squareRoot()
        var height = width / ratio
        if width > bounds.width {
            width = bounds.width
            height = width / ratio
        }
        if height > bounds.height {
            height = bounds.height
            width = height * ratio
        }
        return clamped(CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height))
    }

    /// Rounds edges to whole device pixels so the recorded region matches what the overlay shows.
    func pixelAligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded() / scale
        let minY = (rect.minY * scale).rounded() / scale
        let maxX = (rect.maxX * scale).rounded() / scale
        let maxY = (rect.maxY * scale).rounded() / scale
        return clamped(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private func freeEdgeResize(_ start: CGRect, handle: ResizeHandle, target: CGPoint) -> CGRect {
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if handle.movesMinX { minX = min(target.x, maxX - Self.minimumSide) }
        if handle.movesMaxX { maxX = max(target.x, minX + Self.minimumSide) }
        if handle.movesMinY { minY = min(target.y, maxY - Self.minimumSide) }
        if handle.movesMaxY { maxY = max(target.y, minY + Self.minimumSide) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Dragging an edge with a locked ratio resizes the perpendicular axis around the rect's center.
    private func ratioEdgeResize(_ start: CGRect, handle: ResizeHandle, target: CGPoint, ratio: CGFloat) -> CGRect {
        if handle == .left || handle == .right {
            let growsRight = handle == .right
            let fixedX = growsRight ? start.minX : start.maxX
            let draggedX = growsRight ? max(target.x, fixedX + Self.minimumSide) : min(target.x, fixedX - Self.minimumSide)
            let availableWidth = growsRight ? bounds.maxX - fixedX : fixedX - bounds.minX
            let width = min(abs(draggedX - fixedX), availableWidth, bounds.height * ratio)
            let height = width / ratio
            let y = min(max(start.midY - height / 2, bounds.minY), bounds.maxY - height)
            return CGRect(x: growsRight ? fixedX : fixedX - width, y: y, width: width, height: height)
        }
        let growsUp = handle == .top
        let fixedY = growsUp ? start.minY : start.maxY
        let draggedY = growsUp ? max(target.y, fixedY + Self.minimumSide) : min(target.y, fixedY - Self.minimumSide)
        let availableHeight = growsUp ? bounds.maxY - fixedY : fixedY - bounds.minY
        let height = min(abs(draggedY - fixedY), availableHeight, bounds.width / ratio)
        let width = height * ratio
        let x = min(max(start.midX - width / 2, bounds.minX), bounds.maxX - width)
        return CGRect(x: x, y: growsUp ? fixedY : fixedY - height, width: width, height: height)
    }
}
