import CoreGraphics

/// A line drawn across the screen to show which edge or center the selection locked onto.
struct SnapGuide: Equatable {
    enum Axis { case vertical, horizontal }

    let axis: Axis
    let position: CGFloat
}

/// Magnetic alignment to other windows' edges, the screen edges and the screen center.
struct SnapEngine {
    /// Distance in points within which an edge jumps onto a target.
    static let threshold: CGFloat = 6

    private let edgeXs: [CGFloat]
    private let edgeYs: [CGFloat]
    private let centerX: CGFloat
    private let centerY: CGFloat

    init(bounds: CGRect, windowFrames: [CGRect]) {
        edgeXs = [bounds.minX, bounds.maxX, bounds.midX] + windowFrames.flatMap { [$0.minX, $0.maxX] }
        edgeYs = [bounds.minY, bounds.maxY, bounds.midY] + windowFrames.flatMap { [$0.minY, $0.maxY] }
        centerX = bounds.midX
        centerY = bounds.midY
    }

    /// Snaps the requested axes of a point (the corner or edge being dragged).
    func snap(_ point: CGPoint, snapX: Bool, snapY: Bool) -> (point: CGPoint, guides: [SnapGuide]) {
        var snapped = point
        var guides: [SnapGuide] = []
        if snapX, let target = Self.nearest(to: point.x, in: edgeXs) {
            snapped.x = target
            guides.append(SnapGuide(axis: .vertical, position: target))
        }
        if snapY, let target = Self.nearest(to: point.y, in: edgeYs) {
            snapped.y = target
            guides.append(SnapGuide(axis: .horizontal, position: target))
        }
        return (snapped, guides)
    }

    /// Snaps a moving rect: either side to any target, or its middle to the screen center.
    func snapMove(_ rect: CGRect) -> (rect: CGRect, guides: [SnapGuide]) {
        let horizontal = Self.bestShift(for: [(rect.minX, edgeXs), (rect.maxX, edgeXs), (rect.midX, [centerX])])
        let vertical = Self.bestShift(for: [(rect.minY, edgeYs), (rect.maxY, edgeYs), (rect.midY, [centerY])])
        var guides: [SnapGuide] = []
        if let horizontal { guides.append(SnapGuide(axis: .vertical, position: horizontal.target)) }
        if let vertical { guides.append(SnapGuide(axis: .horizontal, position: vertical.target)) }
        return (rect.offsetBy(dx: horizontal?.delta ?? 0, dy: vertical?.delta ?? 0), guides)
    }

    private static func nearest(to value: CGFloat, in targets: [CGFloat]) -> CGFloat? {
        targets
            .filter { abs($0 - value) <= threshold }
            .min { abs($0 - value) < abs($1 - value) }
    }

    private static func bestShift(for candidates: [(value: CGFloat, targets: [CGFloat])]) -> (delta: CGFloat, target: CGFloat)? {
        candidates
            .compactMap { candidate in nearest(to: candidate.value, in: candidate.targets).map { (delta: $0 - candidate.value, target: $0) } }
            .min { abs($0.delta) < abs($1.delta) }
    }
}
