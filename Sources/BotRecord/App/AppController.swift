import AppKit

/// Composition of the app shell: builds every surface once and routes status-item clicks and hotkeys.
@MainActor
final class AppController {
    private let settings = AppSettings()
    private let recents: RecentRecordingsStore
    private let transcription: TranscriptionService
    private let toasts = ToastPresenter()
    private let permissionWindow = PermissionWindowController()
    private let settingsWindow: SettingsWindowController
    private let sessions: CaptureSessions
    private let claude: ClaudeConnection
    private let popover: PopoverPanelController
    private let hotKeys = HotKeys()
    private var statusItem: StatusItemController?

    init(dependencies: AppDependencies) {
        let recents = RecentRecordingsStore(settings: settings)
        let permissionWindow = permissionWindow
        let transcription = TranscriptionService(settings: settings, models: TranscriptionModelStore())
        self.recents = recents
        self.transcription = transcription
        let sessions = CaptureSessions(
            screen: RecordingCoordinator(
                settings: settings,
                dependencies: dependencies,
                recents: recents,
                transcription: transcription,
                outcomes: toasts,
                permissionPrompt: permissionWindow
            ),
            meeting: MeetingCoordinator(
                settings: settings,
                recorder: dependencies.meetingRecorder,
                hud: dependencies.hud,
                recents: recents,
                transcription: transcription,
                outcomes: toasts,
                permissionPrompt: permissionWindow
            ),
            summaries: SummaryController(settings: settings, recents: recents, summarizer: ClaudeCodeSummarizer()),
            transcription: transcription
        )
        let claude = ClaudeConnection(isCapturing: { [sessions] in sessions.isCapturing })
        let settingsWindow = SettingsWindowController(settings: settings, transcription: transcription, connection: claude) {
            ScreenCapturePermission.request()
            permissionWindow.presentPermissionRequest()
        }
        self.sessions = sessions
        self.claude = claude
        self.settingsWindow = settingsWindow
        popover = PopoverPanelController(
            settings: settings,
            sessions: sessions,
            recents: recents,
            connection: claude,
            onOpenSettings: { [settingsWindow] in settingsWindow.show() }
        )
    }

    func start() {
        // A menu-bar app has no windows most of the time; without this macOS may quit it as idle.
        ProcessInfo.processInfo.disableAutomaticTermination("BotRecord lives in the menu bar")
        CompanionCache.purgeExpired()
        recents.reload()
        registerHotKeys()
        claude.refresh()
        statusItem = StatusItemController(display: { [sessions] in sessions.statusDisplay }) { [weak self] in
            self?.statusItemClicked()
        }
    }

    private func statusItemClicked() {
        guard !sessions.handleStatusItemClick(), let button = statusItem?.button else { return }
        popover.toggle(below: button)
    }

    private func registerHotKeys() {
        register(.toggleRecording) { [sessions] in sessions.toggleScreenRecording() }
        register(.recordArea) { [sessions] in sessions.startScreenRecording(mode: .area) }
        register(.toggleMeeting) { [sessions] in sessions.toggleMeeting() }
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
