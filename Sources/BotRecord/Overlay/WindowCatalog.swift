import CoreGraphics
import Foundation
import OSLog
import ScreenCaptureKit

/// Frames of the windows a click can select, so the selection can snap to them and hover can highlight them.
enum WindowCatalog {
    private static let logger = Logger(subsystem: AppPaths.identifier, category: "overlay")
    private static let minimumSide: CGFloat = 40

    /// AppKit-global frames of on-screen, regular-layer windows that are not ours, frontmost first.
    /// Returns an empty list (window hover disabled, free drawing still works) when ScreenCaptureKit refuses.
    static func loadVisibleWindowFrames() async -> [CGRect] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            logger.error("Window list unavailable, window picking disabled: \(error.localizedDescription)")
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let depth = frontToBackDepth()
        return content.windows
            .filter { window in
                window.windowLayer == 0
                    && window.isOnScreen
                    && window.owningApplication?.processID != ownPID
                    && window.frame.width >= minimumSide
                    && window.frame.height >= minimumSide
            }
            .sorted { (depth[$0.windowID] ?? .max) < (depth[$1.windowID] ?? .max) }
            .map { ScreenSpace.appKitRect(fromCoreGraphics: $0.frame) }
    }

    /// ScreenCaptureKit does not document its ordering; CoreGraphics lists on-screen windows front to back.
    private static func frontToBackDepth() -> [CGWindowID: Int] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var depth: [CGWindowID: Int] = [:]
        for (index, entry) in info.enumerated() {
            if let number = entry[kCGWindowNumber as String] as? CGWindowID {
                depth[number] = index
            }
        }
        return depth
    }
}
