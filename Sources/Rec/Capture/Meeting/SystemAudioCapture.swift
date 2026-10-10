import CoreMedia
import ScreenCaptureKit

/// A ScreenCaptureKit stream kept only for its audio (the "Others" track).
///
/// ScreenCaptureKit has no audio-only mode, so the video side is shrunk to the cheapest it accepts:
/// 2×2 px, at most one frame every few seconds, shallow queue, no cursor. Those frames are dropped
/// unread; a `.screen` output is still registered because without one ScreenCaptureKit logs an error
/// for every frame it cannot deliver.
final class SystemAudioCapture {
    private static let idleFrameInterval = CMTime(value: 5, timescale: 1)
    private static let minimumQueueDepth = 3

    private let stream: SCStream
    private let output: Output

    /// - Parameters:
    ///   - queue: serial queue `onAudio` runs on; buffers carry host-clock timestamps.
    ///   - onError: the stream died (permission revoked, display gone).
    init(filter: SCContentFilter, queue: DispatchQueue,
         onAudio: @escaping (CMSampleBuffer) -> Void, onError: @escaping @Sendable (Error) -> Void) throws {
        output = Output(onAudio: onAudio, onError: onError)
        stream = SCStream(filter: filter, configuration: Self.configuration(), delegate: output)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
    }

    func start() async throws {
        try await stream.startCapture()
    }

    /// Stops delivery; buffers already queued still reach `onAudio` before later work on the same queue.
    func stop() async {
        do {
            try await stream.stopCapture()
        } catch {
            // Expected when the stream already died on its own; what was captured is kept regardless.
            captureLog.error("Meeting audio stopCapture failed: \(error.localizedDescription)")
        }
    }

    private static func configuration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = idleFrameInterval
        configuration.queueDepth = minimumQueueDepth
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = StreamConfiguration.audioSampleRate
        configuration.channelCount = StreamConfiguration.audioChannelCount
        return configuration
    }

    private final class Output: NSObject, SCStreamOutput, SCStreamDelegate {
        private let onAudio: (CMSampleBuffer) -> Void
        private let onError: @Sendable (Error) -> Void

        init(onAudio: @escaping (CMSampleBuffer) -> Void, onError: @escaping @Sendable (Error) -> Void) {
            self.onAudio = onAudio
            self.onError = onError
        }

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
            guard type == .audio, sampleBuffer.isValid, sampleBuffer.numSamples > 0 else { return }
            onAudio(sampleBuffer)
        }

        func stream(_ stream: SCStream, didStopWithError error: Error) {
            onError(error)
        }
    }
}
