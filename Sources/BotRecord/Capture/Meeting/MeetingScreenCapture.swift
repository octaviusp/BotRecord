import CoreMedia
import ScreenCaptureKit

/// The optional `video.webm` of a meeting: the whole main display through the regular AV1 path.
/// Its stream carries no audio; `MeetingAudioRouter` feeds the writer the mix of both voices,
/// so the video plays on its own.
final class MeetingScreenCapture {
    let url: URL
    /// Receives the voice mix as source `.system`.
    let writer: WebMAV1Writer
    private let stream: SCStream
    private let handler: CaptureSampleHandler

    init(display: SCDisplay, content: SCShareableContent, options: RecordingOptions, url: URL,
         clock: RecordingClock, onError: @escaping @Sendable (Error) -> Void) throws {
        var videoOnly = options
        videoOnly.captureSystemAudio = false
        videoOnly.captureMicrophone = false
        let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let setup = try StreamConfiguration.make(display: display, sourceRect: nil, excluding: ownApplications, options: videoOnly)

        let config = VideoEncodeConfig(
            width: setup.outputSize.width,
            height: setup.outputSize.height,
            frameRate: options.frameRate.rawValue,
            compression: options.compression,
            audioSources: [.system]
        )
        writer = try WebMAV1Writer(url: url, config: config)
        handler = CaptureSampleHandler(sinks: [writer], clock: clock, frameRate: options.frameRate.rawValue, onError: onError)
        stream = SCStream(filter: setup.filter, configuration: setup.configuration, delegate: handler)
        do {
            try stream.addStreamOutput(handler, type: .screen, sampleHandlerQueue: handler.queue)
        } catch {
            writer.cancel()
            throw error
        }
        self.url = url
    }

    func start() async throws {
        try await stream.startCapture()
    }

    /// Stops the stream and drains in-flight frames. With `finalTime` the last frame is repeated up to it,
    /// so a static screen still lasts until the stop.
    func halt(extendingTo finalTime: CMTime?) async {
        do {
            try await stream.stopCapture()
        } catch {
            // Expected when the stream already died on its own; the writer is finalized regardless.
            captureLog.error("Meeting screen stopCapture failed: \(error.localizedDescription)")
        }
        _ = await handler.close(extendingTimelineTo: finalTime)
    }

    func finish() async throws {
        try await writer.finish()
    }

    /// Deletes `video.webm`.
    func cancel() {
        writer.cancel()
    }
}
