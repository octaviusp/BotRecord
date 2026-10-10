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

    /// macOS only applies a new Screen Recording grant to a fresh process, so restart Rec in place.
    static func relaunchApp() throws {
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundleURL.path]
        try relauncher.run()
        NSApp.terminate(nil)
    }
}
