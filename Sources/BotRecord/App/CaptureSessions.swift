import AppKit

/// Routes every entry point (hotkeys, popover, status item) to the screen or meeting coordinator,
/// keeping them mutually exclusive: only one capture runs at a time.
@MainActor
final class CaptureSessions {
    let screen: RecordingCoordinator
    let meeting: MeetingCoordinator
    let summaries: SummaryController
    let transcription: TranscriptionService

    init(screen: RecordingCoordinator, meeting: MeetingCoordinator, summaries: SummaryController,
         transcription: TranscriptionService) {
        self.screen = screen
        self.meeting = meeting
        self.summaries = summaries
        self.transcription = transcription
    }

    var isFailed: Bool { screen.phase == .failed || meeting.phase == .failed }

    /// A screen recording or meeting is being set up, running or saved.
    var isCapturing: Bool { isScreenBusy || meeting.isBusy }

    /// ⌃⌥⌘R: start/stop a screen recording. Never stops a meeting, so a reflex press can't end the notes.
    func toggleScreenRecording() {
        guard !meeting.isBusy else { return NSSound.beep() }
        screen.toggleRecording()
    }

    func startScreenRecording(mode: CaptureMode) {
        guard !meeting.isBusy else { return NSSound.beep() }
        screen.startRecording(mode: mode)
    }

    /// ⌃⌥⌘M: start/stop meeting notes.
    func toggleMeeting() {
        guard !isScreenBusy else { return NSSound.beep() }
        meeting.toggle()
    }

    /// The popover's record button, in whatever mode its tiles show.
    func start(_ mode: RecorderMode) {
        if let captureMode = mode.captureMode {
            startScreenRecording(mode: captureMode)
        } else {
            guard !isScreenBusy else { return NSSound.beep() }
            meeting.start()
        }
    }

    /// Handles a status-item click; returns false when the click should open the popover instead.
    func handleStatusItemClick() -> Bool {
        switch meeting.phase {
        case .recording: meeting.stop(); return true
        case .paused: meeting.resume(); return true
        case .starting, .saving, .discarding: return true
        case .idle, .failed: break
        }
        switch screen.phase {
        case .recording: screen.stop(); return true
        case .paused: screen.resume(); return true
        case .selectingArea, .countdown, .starting, .saving, .discarding: return true
        case .idle, .failed: return false
        }
    }

    private var isScreenBusy: Bool { screen.phase != .idle && screen.phase != .failed }
}
