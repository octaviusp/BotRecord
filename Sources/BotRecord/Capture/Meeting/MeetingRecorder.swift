import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Records a call from any app: every app's audio ("Others") and the microphone ("Me") as two Opus
/// tracks of `audio.webm`, plus an optional `video.webm` of the main display.
@MainActor
final class MeetingRecorder: MeetingRecording {
    private enum Phase { case idle, starting, recording, finishing }

    /// Everything that exists only while a meeting is being recorded.
    private struct ActiveMeeting {
        let clock: RecordingClock
        let router: MeetingAudioRouter
        let systemAudio: SystemAudioCapture
        let microphone: MicrophoneCapture?
        let screen: MeetingScreenCapture?
        let folder: URL
        let audioURL: URL
        let startedAt: Date
    }

    private struct Finalized {
        let audioError: Error?
        let videoURL: URL?
        let duration: TimeInterval
    }

    var onFailure: ((RecordingFailure) -> Void)?

    var audioObserver: LiveAudioObserver? {
        get { observers.current }
        set { observers.current = newValue }
    }

    var isPaused: Bool { active?.clock.isPaused ?? false }

    var elapsed: TimeInterval {
        active?.clock.elapsedTime(at: RecordingClock.hostNow).seconds ?? 0
    }

    private let observers = LiveAudioObserverSlot()
    private var phase = Phase.idle
    private var active: ActiveMeeting?

    init() {}

    // MARK: Start

    func start(_ options: MeetingOptions) async throws {
        guard phase == .idle else { throw CaptureError.alreadyRecording }
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.screenRecordingPermissionMissing }
        phase = .starting
        do {
            active = try await begin(options)
            phase = .recording
        } catch {
            phase = .idle
            throw error
        }
    }

    private func begin(_ options: MeetingOptions) async throws -> ActiveMeeting {
        if options.captureMicrophone { try await MicrophoneCapture.requestPermission() }
        // Includes apps whose windows are all minimized or on another Space: a call app often is.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let mainDisplayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) else {
            throw CaptureError.displayNotFound(mainDisplayID)
        }
        // Every app's audio except BotRecord's own. A per-app filter would miss Chrome, Discord or Teams, whose
        // sound comes from helper processes ScreenCaptureKit does not list.
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        try FileManager.default.createDirectory(at: options.folder, withIntermediateDirectories: true)

        let clock = RecordingClock()
        let reportFailure: @Sendable (Error) -> Void = { [weak self] error in
            Task { @MainActor in await self?.handleFailure(error) }
        }
        let tracks: [MeetingTrack] = options.captureMicrophone ? [.me, .others] : [.others]
        let audioURL = options.folder.appendingPathComponent("audio.webm")
        let writer = try MultiTrackAudioWriter(url: audioURL, tracks: tracks.map(Self.fileTrack))

        var screen: MeetingScreenCapture?
        var router: MeetingAudioRouter?
        var systemAudio: SystemAudioCapture?
        var microphone: MicrophoneCapture?
        do {
            screen = try options.screen.map {
                try MeetingScreenCapture(display: display, content: content, options: $0,
                                         url: options.folder.appendingPathComponent("video.webm"),
                                         clock: clock, onError: reportFailure)
            }
            let audioRouter = try MeetingAudioRouter(writer: writer, tracks: tracks, clock: clock, observers: observers,
                                                     videoWriter: screen?.writer, onError: reportFailure)
            router = audioRouter
            let others = try SystemAudioCapture(filter: filter, queue: audioRouter.queue,
                                                onAudio: { audioRouter.receiveSystemAudio($0) }, onError: reportFailure)
            try await others.start()
            systemAudio = others
            if options.captureMicrophone {
                let mic = MicrophoneCapture(echoCancellation: options.echoCancellation,
                                            onBuffer: { audioRouter.receiveMicrophone($0) },
                                            onLost: { [weak self] error in Task { await self?.handleFailure(error) } })
                try mic.start()
                microphone = mic
            }
            // Last: its first frame fixes time zero, and voice processing alone can take a second to start.
            try await screen?.start()
            clock.startTimeline(at: RecordingClock.hostNow)
            audioRouter.startHeartbeat()
            return ActiveMeeting(
                clock: clock, router: audioRouter, systemAudio: others, microphone: microphone, screen: screen,
                folder: options.folder, audioURL: audioURL, startedAt: Date()
            )
        } catch {
            microphone?.stop()
            await systemAudio?.stop()
            await screen?.halt(extendingTo: nil)
            screen?.cancel()
            if let router { await router.cancel() } else { writer.cancel() }
            throw error
        }
    }

    // MARK: Pause / resume

    func pause() {
        active?.clock.pause(at: RecordingClock.hostNow)
    }

    func resume() {
        active?.clock.resume(at: RecordingClock.hostNow)
    }

    // MARK: Stop / cancel

    func stop() async throws -> MeetingCaptureResult {
        guard phase == .recording, let meeting = active else { throw CaptureError.notRecording }
        phase = .finishing
        defer { reset() }
        let finalized = await finalize(meeting, extendingVideo: true)
        if let audioError = finalized.audioError { throw audioError }
        return MeetingCaptureResult(
            folder: meeting.folder, audioURL: meeting.audioURL, videoURL: finalized.videoURL,
            startedAt: meeting.startedAt, duration: finalized.duration
        )
    }

    func cancel() async {
        guard phase == .recording, let meeting = active else { return }
        phase = .finishing
        await halt(meeting, extendingVideo: false)
        await meeting.router.cancel()
        meeting.screen?.cancel()
        reset()
    }

    // MARK: Failure

    /// A dead stream, a lost microphone or a write error (disk full): finalize what exists and report once.
    private func handleFailure(_ error: Error) async {
        guard phase == .recording, let meeting = active else { return }
        phase = .finishing
        captureLog.error("Meeting recording failed: \(error.localizedDescription)")
        let finalized = await finalize(meeting, extendingVideo: false)
        if let audioError = finalized.audioError {
            captureLog.error("Partial meeting audio could not be finalized: \(audioError.localizedDescription)")
        }
        reset()
        // The contract's partial result describes a screen recording; the finalized files stay in the folder.
        onFailure?(RecordingFailure(message: FailureMessage.describe(error), underlying: error, partialResult: nil))
    }

    // MARK: Teardown

    /// Freezes the timeline and stops every capture, so no more samples arrive.
    @discardableResult
    private func halt(_ meeting: ActiveMeeting, extendingVideo: Bool) async -> CMTime {
        let stopTime = RecordingClock.hostNow
        meeting.clock.pause(at: stopTime)
        let finalTime = meeting.clock.elapsedTime(at: stopTime)
        meeting.microphone?.stop()
        await meeting.systemAudio.stop()
        await meeting.screen?.halt(extendingTo: extendingVideo ? finalTime : nil)
        return finalTime
    }

    /// Stops capturing and finalizes both files. A video failure only costs the video: the audio is the meeting.
    private func finalize(_ meeting: ActiveMeeting, extendingVideo: Bool) async -> Finalized {
        let finalTime = await halt(meeting, extendingVideo: extendingVideo)
        let finalFrame = Int64((finalTime.seconds * Double(StereoPCMChunk.sampleRate)).rounded())
        let audioError = await meeting.router.finish(through: finalFrame)

        var videoURL: URL?
        if let screen = meeting.screen {
            do {
                try await screen.finish()
                videoURL = screen.url
            } catch {
                captureLog.error("Meeting video failed, keeping the audio only: \(error.localizedDescription)")
                OutputFiles.removeIfPresent(screen.url)
            }
        }
        return Finalized(audioError: audioError, videoURL: videoURL, duration: finalTime.seconds)
    }

    private func reset() {
        active = nil
        phase = .idle
    }

    private static func fileTrack(_ track: MeetingTrack) -> MultiTrackAudioWriter.Track {
        switch track {
        case .me: MultiTrackAudioWriter.Track(name: "Me", opus: .voice)
        case .others: MultiTrackAudioWriter.Track(name: "Others", opus: .callAudio)
        }
    }
}
