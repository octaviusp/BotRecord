import AppKit

/// Maps selection states to the native cursors the design calls for.
@MainActor
enum SelectionCursors {
    private static let moveCursor = makeMoveCursor()

    static func cursor(for state: SelectionCursor) -> NSCursor {
        switch state {
        case .crosshair: .crosshair
        case let .resize(handle): resizeCursor(for: handle)
        case .move: moveCursor
        }
    }

    private static func resizeCursor(for handle: ResizeHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition = switch handle {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    /// AppKit has no public four-way move cursor, so draw the SF Symbol white with a dark halo
    /// (readable over both the scrim and the live screen).
    private static func makeMoveCursor() -> NSCursor {
        let name = "arrow.up.and.down.and.arrow.left.and.right"
        let size = CGSize(width: 26, height: 26)
        func symbol(_ color: NSColor) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .bold).applying(.init(paletteColors: [color])))
        }
        guard let halo = symbol(.black), let glyph = symbol(.white) else { return .openHand }
        let image = NSImage(size: size, flipped: false) { bounds in
            let glyphRect = CGRect(
                x: (bounds.width - glyph.size.width) / 2,
                y: (bounds.height - glyph.size.height) / 2,
                width: glyph.size.width,
                height: glyph.size.height
            )
            for offset in [(-1.0, 0.0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)] {
                halo.draw(in: glyphRect.offsetBy(dx: offset.0, dy: offset.1))
            }
            glyph.draw(in: glyphRect)
            return true
        }
        return NSCursor(image: image, hotSpot: CGPoint(x: size.width / 2, y: size.height / 2))
    }
}
