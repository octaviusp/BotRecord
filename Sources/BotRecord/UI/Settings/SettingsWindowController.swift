import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings, transcription: TranscriptionService, connection: ClaudeConnection,
         onRequestPermission: @escaping () -> Void) {
        let controller = NSHostingController(rootView: SettingsView(
            settings: settings,
            transcription: transcription,
            connection: connection,
            onRequestPermission: onRequestPermission
        ))
        window = NSWindow(contentViewController: controller)
        window.title = "BotRecord Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 760))
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
