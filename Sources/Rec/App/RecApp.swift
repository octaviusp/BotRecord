import SwiftUI

/// Rec lives entirely in the menu bar, so the only scene is an empty `Settings`
/// (SwiftUI requires one); the real windows are AppKit panels owned by `AppController`.
@main
struct RecApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController(dependencies: .live())
        controller.start()
        self.controller = controller
    }
}
