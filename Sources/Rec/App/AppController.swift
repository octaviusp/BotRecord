import AppKit

/// Composition of the app shell: builds every surface once and routes status-item clicks and hotkeys.
@MainActor
final class AppController {
    private let settings = AppSettings()
    private let recents: RecentRecordingsStore
    private let toasts = ToastPresenter()
    private let permissionWindow = PermissionWindowController()
    private let settingsWindow: SettingsWindowController
    private let coordinator: RecordingCoordinator
    private let popover: PopoverPanelController
    private let hotKeys = HotKeys()
    private var statusItem: StatusItemController?

    init(dependencies: AppDependencies) {
        let recents = RecentRecordingsStore(settings: settings)
        let permissionWindow = permissionWindow
        self.recents = recents
        settingsWindow = SettingsWindowController(settings: settings) {
            ScreenCapturePermission.request()
            permissionWindow.presentPermissionRequest()
        }
        coordinator = RecordingCoordinator(
            settings: settings,
            dependencies: dependencies,
            recents: recents,
            outcomes: toasts,
            permissionPrompt: permissionWindow
        )
        popover = PopoverPanelController(
            settings: settings,
            coordinator: coordinator,
            recents: recents,
            onOpenSettings: { [settingsWindow] in settingsWindow.show() }
        )
    }

    func start() {
        // A menu-bar app has no windows most of the time; without this macOS may quit it as idle.
        ProcessInfo.processInfo.disableAutomaticTermination("Rec lives in the menu bar")
        CompanionCache.purgeExpired()
        recents.reload()
        registerHotKeys()
        statusItem = StatusItemController(coordinator: coordinator) { [weak self] in self?.statusItemClicked() }
    }

    private func statusItemClicked() {
        switch coordinator.phase {
        case .recording: coordinator.stop()
        case .paused: coordinator.resume()
        case .idle, .failed:
            if let button = statusItem?.button { popover.toggle(below: button) }
        case .selectingArea, .countdown, .starting, .saving, .discarding: break
        }
    }

    private func registerHotKeys() {
        register(.toggleRecording) { [coordinator] in coordinator.toggleRecording() }
        register(.recordArea) { [coordinator] in coordinator.startRecording(mode: .area) }
    }

    /// One failing shortcut must not disable the other, and the user needs to know which one is taken.
    private func register(_ shortcut: GlobalShortcut, action: @escaping @MainActor () -> Void) {
        do {
            try hotKeys.register(shortcut) { [popover] in
                popover.close()
                action()
            }
        } catch {
            toasts.presentFailure(
                FailurePresentation(title: "Shortcut unavailable", message: error.localizedDescription, partialResult: nil),
                onDismiss: {}
            )
        }
    }
}
