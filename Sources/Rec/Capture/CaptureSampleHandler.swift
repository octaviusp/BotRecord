import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// Receives ScreenCaptureKit samples on one serial queue, rebases their timestamps on the recording
/// clock and fans them out to every sink. All mutable state lives on `queue`.
final class CaptureSampleHandler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "local.tools.screen-recorder.capture", qos: .userInteractive)

    private let sinks: [MediaSink]
    private let clock: RecordingClock
    private let frameInterval: CMTime
    private let onError: @Sendable (Error) -> Void
    private let thumbnailer = Thumbnailer()

    private var isClosed = false
    private var lastVideo: (pixelBuffer: CVPixelBuffer, time: CMTime)?

    init(sinks: [MediaSink], clock: RecordingClock, frameRate: Int, onError: @escaping @Sendable (Error) -> Void) {
        self.sinks = sinks
        self.clock = clock
        self.frameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        self.onError = onError
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isClosed, sampleBuffer.isValid else { return }
        do {
            switch type {
            case .screen: try handleVideo(sampleBuffer)
            case .audio: try handleAudio(sampleBuffer, source: .system)
            case .microphone: try handleAudio(sampleBuffer, source: .microphone)
            @unknown default: break
            }
        } catch {
            // Stop feeding sinks: the recorder finalizes what exists and reports the failure once.
            isClosed = true
            onError(error)
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError(error)
    }

    // MARK: Lifecycle

    /// Drains in-flight samples and stops accepting new ones. When `finalTime` is given, the last frame is
    /// repeated up to it: ScreenCaptureKit sends nothing while the screen is static, so without this the
    /// file would end at the last change instead of at the moment recording stopped.
    func close(extendingTimelineTo finalTime: CMTime?) async -> CGImage? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let finalTime, !self.isClosed { self.extendLastFrame(to: finalTime) }
                self.isClosed = true
                self.lastVideo = nil
                continuation.resume(returning: self.thumbnailer.image)
            }
        }
    }

    // MARK: Samples

    private func handleVideo(_ sampleBuffer: CMSampleBuffer) throws {
        guard Self.isCompleteFrame(sampleBuffer), let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let time = clock.videoTime(for: sampleBuffer.presentationTimeStamp) else { return }
        // Writers reject non-increasing timestamps, which a pause/resume race could otherwise produce.
        if let last = lastVideo, time <= last.time { return }
        for sink in sinks { try sink.appendVideo(pixelBuffer, presentationTime: time) }
        lastVideo = (pixelBuffer, time)
        thumbnailer.offer(pixelBuffer, at: time)
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer, source: AudioSource) throws {
        guard sampleBuffer.numSamples > 0, let time = clock.audioTime(for: sampleBuffer.presentationTimeStamp) else { return }
        let retimed = try sampleBuffer.shiftingTimestamps(to: time)
        for sink in sinks { try sink.appendAudio(retimed, source: source) }
    }

    private func extendLastFrame(to finalTime: CMTime) {
        guard let last = lastVideo, finalTime - last.time > frameInterval + frameInterval else { return }
        do {
            for sink in sinks { try sink.appendVideo(last.pixelBuffer, presentationTime: finalTime) }
        } catch {
            captureLog.error("Could not extend the last frame to the stop time: \(error.localizedDescription)")
        }
    }

    /// ScreenCaptureKit also delivers idle, blank and suspended frames that carry no new pixels.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return false }
        return status == .complete
    }
}

extension CMSampleBuffer {
    /// A copy whose first timestamp is `start`, keeping the spacing between its timing entries.
    func shiftingTimestamps(to start: CMTime) throws -> CMSampleBuffer {
        var entryCount = 0
        try Self.check(CMSampleBufferGetSampleTimingInfoArray(self, entryCount: 0, arrayToFill: nil, entriesNeededOut: &entryCount))
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: entryCount)
        try Self.check(CMSampleBufferGetSampleTimingInfoArray(self, entryCount: entryCount, arrayToFill: &timings, entriesNeededOut: &entryCount))

        let delta = start - presentationTimeStamp
        for index in timings.indices {
            timings[index].presentationTimeStamp = timings[index].presentationTimeStamp + delta
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp = timings[index].decodeTimeStamp + delta
            }
        }

        var shifted: CMSampleBuffer?
        try Self.check(CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: self, sampleTimingEntryCount: entryCount,
            sampleTimingArray: &timings, sampleBufferOut: &shifted
        ))
        guard let shifted else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(kCMSampleBufferError_AllocationFailed)) }
        return shifted
    }

    private static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
