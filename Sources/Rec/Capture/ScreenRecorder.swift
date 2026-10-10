import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenRecorder: ScreenRecording {
    private enum Phase { case idle, starting, recording, finishing }

    var onFailure: ((RecordingFailure) -> Void)?

    private var phase = Phase.idle
    private var active: ActiveRecording?

    var isPaused: Bool { active?.clock.isPaused ?? false }

    var elapsed: TimeInterval {
        guard let active else { return 0 }
        return active.clock.elapsedTime(at: RecordingClock.hostNow).seconds
    }

    init() {}

    // MARK: Start

    func start(target: CaptureTarget, options: RecordingOptions) async throws {
        guard phase == .idle else { throw CaptureError.alreadyRecording }
        guard CGPreflightScreenCaptureAccess() else { throw CaptureError.screenRecordingPermissionMissing }
        phase = .starting
        do {
            active = try await beginCapture(target: target, options: options)
            phase = .recording
        } catch {
            phase = .idle
            throw error
        }
    }

    private func beginCapture(target: CaptureTarget, options: RecordingOptions) async throws -> ActiveRecording {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
            throw CaptureError.displayNotFound(target.displayID)
        }
        let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        if ownApplications.isEmpty {
            captureLog.error("Own application not listed by ScreenCaptureKit; overlays cannot be excluded from the video")
        }

        let setup = try StreamConfiguration.make(
            display: display, sourceRect: target.sourceRect, excluding: ownApplications, options: options
        )
        let sinks = try RecordingSinks.make(options: options, outputSize: setup.outputSize)
        let clock = RecordingClock()
        let handler = CaptureSampleHandler(
            sinks: sinks.all, clock: clock, frameRate: options.frameRate.rawValue
        ) { [weak self] error in
            Task { @MainActor in await self?.handleFailure(error) }
        }

        let stream = SCStream(filter: setup.filter, configuration: setup.configuration, delegate: handler)
        do {
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: handler.queue)
            if options.captureSystemAudio {
                try stream.addStreamOutput(handler, type: .audio, sampleHandlerQueue: handler.queue)
            }
            if options.captureMicrophone {
                try stream.addStreamOutput(handler, type: .microphone, sampleHandlerQueue: handler.queue)
            }
            try await stream.startCapture()
        } catch {
            sinks.cancelAll()
            throw error
        }
        return ActiveRecording(stream: stream, handler: handler, sinks: sinks, clock: clock, pixelSize: setup.outputSize)
    }

    // MARK: Pause / resume

    func pause() {
        active?.clock.pause(at: RecordingClock.hostNow)
    }

    func resume() {
        active?.clock.resume(at: RecordingClock.hostNow)
    }

    // MARK: Stop / cancel

    func stop() async throws -> RecordingResult {
        guard phase == .recording, let recording = active else { throw CaptureError.notRecording }
        phase = .finishing
        defer { reset() }

        let thumbnail = await recording.halt(at: RecordingClock.hostNow, extendingTimeline: true)
        let outcome = await recording.sinks.finishAll()
        if case .failure(let error) = outcome.main {
            if let companion = recording.sinks.companion { OutputFiles.removeIfPresent(companion.url) }
            throw error
        }
        return try makeResult(recording, companionFinished: Self.companionFinished(outcome.companion), thumbnail: thumbnail)
    }

    func cancel() async {
        guard phase == .recording, let recording = active else { return }
        phase = .finishing
        _ = await recording.halt(at: RecordingClock.hostNow, extendingTimeline: false)
        recording.sinks.cancelAll()
        reset()
    }

    // MARK: Failure

    /// A dead stream or a sink error (disk full): finalize whatever exists and report once.
    private func handleFailure(_ error: Error) async {
        guard phase == .recording, let recording = active else { return }
        phase = .finishing
        captureLog.error("Recording failed: \(error.localizedDescription)")

        let thumbnail = await recording.halt(at: RecordingClock.hostNow, extendingTimeline: false)
        let outcome = await recording.sinks.finishAll()
        let partialResult = partialResult(from: recording, outcome: outcome, thumbnail: thumbnail)
        reset()
        onFailure?(RecordingFailure(message: FailureMessage.describe(error), underlying: error, partialResult: partialResult))
    }

    private func partialResult(
        from recording: ActiveRecording,
        outcome: (main: Result<Void, Error>, companion: Result<Void, Error>?),
        thumbnail: CGImage?
    ) -> RecordingResult? {
        if case .failure(let error) = outcome.main {
            captureLog.error("Partial recording could not be finalized: \(error.localizedDescription)")
            return nil
        }
        do {
            return try makeResult(recording, companionFinished: Self.companionFinished(outcome.companion), thumbnail: thumbnail)
        } catch {
            captureLog.error("Partial recording unreadable: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Result

    private func makeResult(_ recording: ActiveRecording, companionFinished: Bool, thumbnail: CGImage?) throws -> RecordingResult {
        let mainURL = recording.sinks.main.url
        let fileSize = try mainURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if let companion = recording.sinks.companion, !companionFinished {
            OutputFiles.removeIfPresent(companion.url)
        }
        return RecordingResult(
            url: mainURL,
            companionMP4URL: companionFinished ? recording.sinks.companion?.url : nil,
            duration: recording.clock.elapsedTime(at: RecordingClock.hostNow).seconds,
            fileSize: Int64(fileSize),
            pixelSize: recording.pixelSize.cgSize,
            format: recording.sinks.format,
            thumbnail: thumbnail
        )
    }

    /// The companion is a convenience: its failure costs "Copy as MP4", never the recording.
    private static func companionFinished(_ result: Result<Void, Error>?) -> Bool {
        switch result {
        case nil:
            return false
        case .success?:
            return true
        case .failure(let error)?:
            captureLog.error("Companion MP4 failed: \(error.localizedDescription)")
            return false
        }
    }

    private func reset() {
        active = nil
        phase = .idle
    }
}
