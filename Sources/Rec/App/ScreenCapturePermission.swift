import AppKit
import CoreGraphics

enum ScreenCapturePermission {
    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Triggers the one-time system prompt; the result arrives later through polling.
    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
