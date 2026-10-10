import AppKit
import Observation
import os

/// Drives one meeting from "Start meeting notes" to a saved folder in the library.
/// Mirrors `RecordingCoordinator`'s phases so the status item and HUD read the same either way.
@MainActor @Observable
final class MeetingCoordinator {
    enum Phase: Equatable {
        case idle
        case starting
        case recording
        case paused
        case saving
        case discarding
        /// An error toast is on screen; a new meeting is still allowed.
        case failed
    }

    private(set) var phase: Phase = .idle
    private(set) var elapsedSeconds = 0

    /// True from the start press until the files are saved or discarded.
    var isBusy: Bool { phase != .idle && phase != .failed }

    private struct ActiveMeeting {
        let id: UUID
        let library: MeetingLibrary
        let folder: URL
        let options: MeetingOptions
        /// Streams `transcript.md`/`.json` into the folder while recording; nil when transcripts are off.
        let transcriber: LiveTranscriber?
    }

    private let settings: AppSettings
    private let recorder: MeetingRecording
    private let hud: RecordingHUDPresenting
    private let recents: RecentRecordingsStore
    private let transcription: TranscriptionService
    private let outcomes: MeetingOutcomePresenting
    private let permissionPrompt: PermissionPresenting
    private let logger = Logger(subsystem: AppPaths.identifier, category: "meeting")

    private var active: ActiveMeeting?
    private var tickTask: Task<Void, Never>?

    private static let tickInterval: Duration = .milliseconds(250)

    init(
        settings: AppSettings,
        recorder: MeetingRecording,
        hud: RecordingHUDPresenting,
        recents: RecentRecordingsStore,
        transcription: TranscriptionService,
        outcomes: MeetingOutcomePresenting,
        permissionPrompt: PermissionPresenting
    ) {
        self.settings = settings
        self.recorder = recorder
        self.hud = hud
        self.recents = recents
        self.transcription = transcription
        self.outcomes = outcomes
        self.permissionPrompt = permissionPrompt
        recorder.onFailure = { [weak self] failure in self?.handleFailure(failure) }
    }

    // MARK: Entry points

    /// ⌃⌥⌘M, the popover button and the status item: start, or stop when already recording.
    func toggle() {
        switch phase {
        case .recording, .paused: stop()
        case .idle, .failed: start()
        case .starting, .saving, .discarding: break
        }
    }

    func start() {
        guard phase == .idle || phase == .failed else { return }
        // Call audio comes through ScreenCaptureKit, which needs the same grant as screen recording.
        guard ScreenCapturePermission.isGranted else {
            ScreenCapturePermission.request()
            permissionPrompt.presentPermissionRequest()
            return
        }
        outcomes.dismissAll()
        phase = .starting
        Task { await runStart() }
    }

    func pause() {
        guard phase == .recording else { return }
        recorder.pause()
        phase = .paused
        tick()
    }

    func resume() {
        guard phase == .paused else { return }
        recorder.resume()
        phase = .recording
        tick()
    }

    func stop() {
        guard phase == .recording || phase == .paused else { return }
        phase = .saving
        endLiveUI()
        Task { await finish() }
    }

    /// No confirmation: the HUD's trash button is deliberate, and the folder only holds this meeting's media.
    func discard() {
        guard phase == .recording || phase == .paused, let active else { return }
        phase = .discarding
        endLiveUI()
        Task {
            await recorder.cancel()
            endTranscript(active, keeping: false)
            deleteFolder(active.folder, in: active.library)
            self.active = nil
            recents.reload()
            phase = .idle
        }
    }

    // MARK: Flow

    private func runStart() async {
        let library = settings.library
        let folder: URL
        do {
            folder = try library.createMeetingFolder(startedAt: Date())
        } catch {
            fail(title: "Can't use the library folder", message: error.localizedDescription)
            return
        }
        let options = settings.meetingOptions(folder: folder)
        let transcriber = settings.meetingTranscribe ? transcription.startLive(output: MeetingTranscriptFiles(folder: folder)) : nil
        recorder.audioObserver = transcriber
        do {
            try await recorder.start(options)
        } catch {
            recorder.audioObserver = nil
            if let transcriber { transcription.cancel(transcriber) }
            // Nothing was recorded; an empty folder would only clutter the library.
            deleteFolder(folder, in: library)
            fail(title: "Couldn't start meeting notes", message: error.localizedDescription)
            return
        }
        active = ActiveMeeting(id: UUID(), library: library, folder: folder, options: options, transcriber: transcriber)
        elapsedSeconds = 0
        phase = .recording
        // The HUD lives on the main display; a whole-display target means no area outline.
        hud.show(for: CaptureTarget(displayID: CGMainDisplayID(), sourceRect: nil), actions: hudActions)
        beginTicking()
    }

    private func finish() async {
        guard let active else { return }
        do {
            let capture = try await recorder.stop()
            try MeetingMetadata(id: active.id, capture: capture, options: active.options).write(to: capture.folder)
            self.active = nil
            recents.reload()
            phase = .idle
            outcomes.presentMeetingSaved(SavedMeeting(folder: capture.folder, duration: capture.duration))
            endTranscript(active, keeping: true)
        } catch {
            self.active = nil
            endTranscript(active, keeping: false)
            fail(title: "Couldn't save the meeting", message: error.localizedDescription)
        }
    }

    // MARK: Transcript

    /// The recorder delivered its last audio: finish the transcript in the background (Recent shows
    /// "transcribing…" for the fraction of a second it takes), or drop it with the meeting.
    private func endTranscript(_ meeting: ActiveMeeting, keeping: Bool) {
        recorder.audioObserver = nil
        guard let transcriber = meeting.transcriber else { return }
        guard keeping else { return transcription.cancel(transcriber) }
        Task {
            let outcome = await transcription.finish(transcriber, output: nil, trackedAs: meeting.folder)
            listPresentFiles(in: meeting.folder)
            recents.reload()
            if let error = outcome.error {
                outcomes.presentFailure(FailurePresentation(
                    title: "Transcript incomplete",
                    message: "\(error.localizedDescription) The audio is saved; what was transcribed is in transcript.md.",
                    partialResult: nil
                ), onDismiss: {})
            }
        }
    }

    /// meta.json lists the folder's files; the final transcript may be written after it.
    private func listPresentFiles(in folder: URL) {
        do {
            var metadata = try MeetingMetadata.read(from: folder)
            metadata.files = MeetingFiles.present(in: folder)
            try metadata.write(to: folder)
        } catch {
            logger.error("Could not update meta.json files: \(error.localizedDescription)")
        }
    }

    // MARK: Failures

    /// The recorder already finalized what it had: keep it in the library when audio made it to disk.
    private func handleFailure(_ failure: RecordingFailure) {
        guard phase == .recording || phase == .paused, let active else { return }
        endLiveUI()
        self.active = nil
        let audioSaved = FileManager.default.fileExists(atPath: active.folder.appendingPathComponent(MeetingFiles.audio).path)
        endTranscript(active, keeping: audioSaved)
        if audioSaved {
            savePartialMetadata(for: active)
        } else {
            deleteFolder(active.folder, in: active.library)
        }
        recents.reload()
        let savedNote = audioSaved ? " The first \(Formatters.duration(recorder.elapsed)) is saved in the library." : ""
        fail(title: "Meeting notes stopped", message: failure.message + savedNote)
    }

    private func savePartialMetadata(for active: ActiveMeeting) {
        let capture = MeetingCaptureResult(
            folder: active.folder,
            audioURL: active.folder.appendingPathComponent(MeetingFiles.audio),
            videoURL: nil,
            startedAt: Date().addingTimeInterval(-recorder.elapsed),
            duration: recorder.elapsed
        )
        do {
            try MeetingMetadata(id: active.id, capture: capture, options: active.options).write(to: active.folder)
        } catch {
            logger.error("Could not write meta.json for a partial meeting: \(error.localizedDescription)")
        }
    }

    private func deleteFolder(_ folder: URL, in library: MeetingLibrary) {
        do {
            try library.discard(folder)
        } catch {
            logger.error("Could not delete \(folder.path): \(error.localizedDescription)")
        }
    }

    private func fail(title: String, message: String) {
        phase = .failed
        outcomes.presentFailure(FailurePresentation(title: title, message: message, partialResult: nil)) { [weak self] in
            guard self?.phase == .failed else { return }
            self?.phase = .idle
        }
    }

    // MARK: Live UI

    private var hudActions: RecordingHUDActions {
        RecordingHUDActions(
            pause: { [weak self] in self?.pause() },
            resume: { [weak self] in self?.resume() },
            stop: { [weak self] in self?.stop() },
            discard: { [weak self] in self?.discard() }
        )
    }

    private func endLiveUI() {
        tickTask?.cancel()
        tickTask = nil
        hud.dismiss()
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

    private func tick() {
        let seconds = Int(recorder.elapsed)
        if seconds != elapsedSeconds { elapsedSeconds = seconds }
        hud.update(elapsed: recorder.elapsed, isPaused: recorder.isPaused)
    }
}
