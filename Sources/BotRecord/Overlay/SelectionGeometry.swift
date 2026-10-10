import CoreGraphics

/// Resize handles of the selection rectangle. Coordinates are AppKit's (y grows upward), so "top" is `maxY`.
enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    static let corners: [ResizeHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
    static let edges: [ResizeHandle] = [.top, .right, .bottom, .left]

    var isCorner: Bool { Self.corners.contains(self) }
    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var movesMaxY: Bool { self == .topLeft || self == .top || self == .topRight }

    var opposite: ResizeHandle {
        switch self {
        case .topLeft: .bottomRight
        case .top: .bottom
        case .topRight: .bottomLeft
        case .right: .left
        case .bottomRight: .topLeft
        case .bottom: .top
        case .bottomLeft: .topRight
        case .left: .right
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

enum AspectPreset: CaseIterable, Identifiable {
    case free, sixteenNine, sixteenTen, square

    var id: Self { self }

    var title: String {
        switch self {
        case .free: "Free"
        case .sixteenNine: "16:9"
        case .sixteenTen: "16:10"
        case .square: "1:1"
        }
    }

    /// Width over height; nil leaves the shape unconstrained.
    var ratio: CGFloat? {
        switch self {
        case .free: nil
        case .sixteenNine: 16.0 / 9.0
        case .sixteenTen: 16.0 / 10.0
        case .square: 1
        }
    }
}

enum SelectionLimits {
    /// Smallest output the encoders produce a usable video for, in pixels.
    static let minimumPixelSize = (width: 320, height: 180)
}

/// Names the common aspect ratios so the size label can say "16:10" instead of leaving the user to divide.
enum AspectNaming {
    private static let known: [(name: String, ratio: CGFloat)] = [
        ("16:9", 16.0 / 9.0), ("16:10", 16.0 / 10.0), ("4:3", 4.0 / 3.0), ("3:2", 3.0 / 2.0),
        ("1:1", 1), ("21:9", 21.0 / 9.0), ("2:1", 2), ("5:4", 5.0 / 4.0), ("9:16", 9.0 / 16.0), ("3:4", 3.0 / 4.0),
    ]
    private static let tolerance: CGFloat = 0.005

    static func name(forPixelWidth width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else { return nil }
        let ratio = CGFloat(width) / CGFloat(height)
        return known.first { abs(ratio - $0.ratio) / $0.ratio < tolerance }?.name
    }
}
