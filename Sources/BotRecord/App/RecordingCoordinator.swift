import AppKit
import Observation

/// Drives one recording from the Record press to the saved file.
/// Every surface (popover, status item, HUD, hotkeys) calls this; none of them hold state of their own.
@MainActor @Observable
final class RecordingCoordinator {
    enum Phase: Equatable {
        case idle
        case selectingArea
        case countdown
        /// Countdown finished, recorder spinning up.
        case starting
        case recording
        case paused
        case saving
        case discarding
        /// An error toast is on screen; a new recording is still allowed.
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsedSeconds = 0
    private(set) var countdownRemaining = 0
    /// Brief confirmation when auto-copy ran without a toast to show it.
    private(set) var showsCopiedConfirmation = false

    private let settings: AppSettings
    private let dependencies: AppDependencies
    private let recents: RecentRecordingsStore
    private let transcription: TranscriptionService
    private let outcomes: RecordingOutcomePresenting
    private let permissionPrompt: PermissionPresenting

    private var activeOptions: RecordingOptions?
    /// Listens to the recording's audio when "Transcript" is on; finished into files next to the video.
    private var transcriber: LiveTranscriber?
    private var tickTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?

    private static let tickInterval: Duration = .milliseconds(250)
    private static let confirmationDuration: Duration = .milliseconds(1500)

    init(
        settings: AppSettings,
        dependencies: AppDependencies,
        recents: RecentRecordingsStore,
        transcription: TranscriptionService,
        outcomes: RecordingOutcomePresenting,
        permissionPrompt: PermissionPresenting
    ) {
        self.settings = settings
        self.dependencies = dependencies
        self.recents = recents
        self.transcription = transcription
        self.outcomes = outcomes
        self.permissionPrompt = permissionPrompt
        dependencies.recorder.onFailure = { [weak self] failure in self?.handleFailure(failure) }
    }

    // MARK: Entry points

    /// ⌃⌥⌘R and the record controls: start in the current mode, or stop when already recording.
    func toggleRecording() {
        switch phase {
        case .recording, .paused: stop()
        case .idle, .failed: startRecording(mode: settings.mode)
        case .selectingArea, .countdown, .starting, .saving, .discarding: break
        }
    }

    func startRecording(mode: CaptureMode) {
        guard phase == .idle || phase == .failed else { return }
        guard ScreenCapturePermission.isGranted else {
            ScreenCapturePermission.request()
            permissionPrompt.presentPermissionRequest()
            return
        }
        outcomes.dismissAll()
        phase = mode == .area ? .selectingArea : .starting
        Task { await runStartFlow(mode: mode) }
    }

    func pause() {
        guard phase == .recording else { return }
        dependencies.recorder.pause()
        phase = .paused
        tick()
    }

    func resume() {
        guard phase == .paused else { return }
        dependencies.recorder.resume()
        phase = .recording
        tick()
    }

    func stop() {
        guard phase == .recording || phase == .paused else { return }
        phase = .saving
        stopTicking()
        dependencies.hud.dismiss()
        Task { await finishRecording() }
    }

    func discard() {
        guard phase == .recording || phase == .paused else { return }
        phase = .discarding
        stopTicking()
        dependencies.hud.dismiss()
        Task {
            await dependencies.recorder.cancel()
            endTranscript(savingNextTo: nil)
            phase = .idle
        }
    }

    // MARK: Start flow

    private func runStartFlow(mode: CaptureMode) async {
        let options = settings.recordingOptions
        do {
            try FileManager.default.createDirectory(at: options.outputDirectory, withIntermediateDirectories: true)
        } catch {
            fail(title: "Can't use the save folder", message: error.localizedDescription)
            return
        }
        guard let target = await resolveTarget(mode: mode, options: options),
              await runCountdown(target: target) else {
            phase = .idle
            return
        }
        phase = .starting
        let hasAudio = options.captureMicrophone || options.captureSystemAudio
        transcriber = settings.transcribeRecordings && hasAudio ? transcription.startLive(output: nil) : nil
        dependencies.recorder.audioObserver = transcriber
        do {
            try await dependencies.recorder.start(target: target, options: options)
        } catch {
            endTranscript(savingNextTo: nil)
            fail(title: "Couldn't start recording", message: error.localizedDescription)
            return
        }
        activeOptions = options
        elapsedSeconds = 0
        phase = .recording
        dependencies.hud.show(for: target, actions: hudActions)
        beginTicking()
    }

    private func resolveTarget(mode: CaptureMode, options: RecordingOptions) async -> CaptureTarget? {
        switch mode {
        case .fullScreen:
            return CaptureTarget(displayID: Self.displayUnderCursor(), sourceRect: nil)
        case .area:
            let badge = "\(options.resolution.label) · \(options.frameRate.label)"
            return await dependencies.areaSelector.selectArea(AreaSelectionRequest(qualityBadge: badge))
        }
    }

    /// Shows the number in the status item while the overlay counts, since the overlay only reports the end.
    private func runCountdown(target: CaptureTarget) async -> Bool {
        let seconds = settings.countdownSeconds
        guard seconds > 0 else { return true }
        phase = .countdown
        countdownRemaining = seconds
        let ticker = Task {
            while countdownRemaining > 1 {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                countdownRemaining -= 1
            }
        }
        defer { ticker.cancel() }
        return await dependencies.countdown.run(seconds: seconds, target: target)
    }

    private static func displayUnderCursor() -> CGDirectDisplayID {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.displayID ?? CGMainDisplayID()
    }

    // MARK: Finish

    private func finishRecording() async {
        do {
            let result = try await dependencies.recorder.stop()
            complete(result)
            endTranscript(savingNextTo: result.url)
        } catch {
            endTranscript(savingNextTo: nil)
            fail(title: "Couldn't save the recording", message: error.localizedDescription)
        }
    }

    /// Writes `<name>.md` and `<name>.vtt` next to the video in the background, or drops the transcript.
    private func endTranscript(savingNextTo videoURL: URL?) {
        dependencies.recorder.audioObserver = nil
        guard let transcriber else { return }
        self.transcriber = nil
        guard let videoURL else { return transcription.cancel(transcriber) }
        Task {
            let outcome = await transcription.finish(transcriber, output: RecordingTranscriptFiles(videoURL: videoURL),
                                                     trackedAs: videoURL)
            recents.reload()
            if let error = outcome.error {
                outcomes.presentFailure(FailurePresentation(
                    title: "Transcript incomplete", message: error.localizedDescription, partialResult: nil
                ), onDismiss: {})
            }
        }
    }

    private func complete(_ result: RecordingResult) {
        phase = .idle
        Task { await recents.remember(result) }

        var copyError: Error?
        if settings.autoCopy {
            do { try FileClipboard.copy(result.url) } catch { copyError = error }
        }
        let copied = settings.autoCopy && copyError == nil

        if settings.showPreview || copyError != nil {
            let options = activeOptions ?? settings.recordingOptions
            outcomes.presentSaved(SavedRecording(
                result: result,
                qualityLabel: "\(options.resolution.rawValue)p \(options.frameRate.rawValue)",
                alreadyCopied: copied
            ))
        } else if copied {
            confirmCopied()
        }
    }

    private func confirmCopied() {
        showsCopiedConfirmation = true
        confirmationTask?.cancel()
        confirmationTask = Task {
            do { try await Task.sleep(for: Self.confirmationDuration) } catch { return }
            showsCopiedConfirmation = false
        }
    }

    // MARK: Failures

    private func handleFailure(_ failure: RecordingFailure) {
        guard phase == .recording || phase == .paused else { return }
        stopTicking()
        dependencies.hud.dismiss()
        if let partial = failure.partialResult {
            Task { await recents.remember(partial) }
        }
        endTranscript(savingNextTo: failure.partialResult?.url)
        let savedNote = failure.partialResult.map { " Your first \(Formatters.duration($0.duration)) is saved and safe." } ?? ""
        present(FailurePresentation(
            title: "Recording stopped",
            message: failure.message + savedNote,
            partialResult: failure.partialResult
        ))
    }

    private func fail(title: String, message: String) {
        present(FailurePresentation(title: title, message: message, partialResult: nil))
    }

    private func present(_ failure: FailurePresentation) {
        phase = .failed
        outcomes.presentFailure(failure) { [weak self] in
            guard self?.phase == .failed else { return }
            self?.phase = .idle
        }
    }

    // MARK: Ticking

    private var hudActions: RecordingHUDActions {
        RecordingHUDActions(
            pause: { [weak self] in self?.pause() },
            resume: { [weak self] in self?.resume() },
            stop: { [weak self] in self?.stop() },
            discard: { [weak self] in self?.discard() }
        )
    }

    private func beginTicking() {
        tickTask?.cancel()
        tickTask = Task {
            while !Task.isCancelled {
                tick()
                do { try await Task.sleep(for: Self.tickInterval) } catch { return }
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        let recorder = dependencies.recorder
        let seconds = Int(recorder.elapsed)
        if seconds != elapsedSeconds { elapsedSeconds = seconds }
        dependencies.hud.update(elapsed: recorder.elapsed, isPaused: recorder.isPaused)
    }
}
