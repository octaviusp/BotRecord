import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Everything that exists only while a recording is running.
struct ActiveRecording {
    let stream: SCStream
    let handler: CaptureSampleHandler
    let sinks: RecordingSinks
    let clock: RecordingClock
    let pixelSize: CaptureGeometry.PixelSize

    /// Freezes the clock, stops the stream and drains the capture queue. Returns the thumbnail captured
    /// so far. With `extendingTimeline` the last frame is repeated up to the stop time (see `close`).
    func halt(at stopTime: CMTime, extendingTimeline: Bool) async -> CGImage? {
        clock.pause(at: stopTime)
        do {
            try await stream.stopCapture()
        } catch {
            // Expected when the stream already died on its own; the sinks are finalized regardless.
            captureLog.error("stopCapture failed: \(error.localizedDescription)")
        }
        return await handler.close(extendingTimelineTo: extendingTimeline ? clock.elapsedTime(at: stopTime) : nil)
    }
}
