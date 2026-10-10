import AppKit

/// Conversions between the coordinate spaces the overlays juggle:
/// - AppKit global: bottom-left origin, primary screen at zero.
/// - CoreGraphics global (ScreenCaptureKit window frames): top-left origin, same primary screen.
/// - Screen-local: relative to one screen's origin, bottom-left (views) or top-left (`CaptureTarget.sourceRect`).
enum ScreenSpace {
    static func screen(forDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id }
    }

    /// Both CoreGraphics and AppKit globals flip around the primary screen's height.
    static var primaryScreenHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func appKitRect(fromCoreGraphics rect: CGRect) -> CGRect {
        flippedVertically(rect, within: primaryScreenHeight)
    }

    /// Mirrors a rect inside a space of the given height. Flipping twice is the identity, so this
    /// converts bottom-left <-> top-left in either direction.
    static func flippedVertically(_ rect: CGRect, within height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// AppKit global frame of a capture rect (screen-local, top-left origin).
    static func appKitRect(fromCaptureRect rect: CGRect, on screen: NSScreen) -> CGRect {
        flippedVertically(rect, within: screen.frame.height).offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
    }
}
