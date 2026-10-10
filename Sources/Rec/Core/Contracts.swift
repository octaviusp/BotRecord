import AppKit
import CoreMedia
import CoreVideo

/// Encoded-file writer. Called from the capture queue, never the main thread.
/// Timestamps start at zero and already exclude paused time.
protocol MediaSink: AnyObject {
    func appendVideo(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) throws
    func appendAudio(_ sampleBuffer: CMSampleBuffer, source: AudioSource) throws
    /// Flushes encoders and finalizes the container (duration, cues). Safe to call once.
    func finish() async throws
    /// Stops without finalizing and deletes the output file.
    func cancel()
}

@MainActor
protocol ScreenRecording: AnyObject {
    var isPaused: Bool { get }
    /// Recorded time, excluding pauses.
    var elapsed: TimeInterval { get }
    /// Called on the main actor when recording dies mid-way; the partial file is already finalized.
    var onFailure: ((RecordingFailure) -> Void)? { get set }
    /// Receives the recorded audio (all sources mixed) for live transcription; read at `start`.
    var audioObserver: LiveAudioObserver? { get set }

    func start(target: CaptureTarget, options: RecordingOptions) async throws
    func pause()
    func resume()
    func stop() async throws -> RecordingResult
    /// Discards the recording and deletes its files.
    func cancel() async
}

struct AreaSelectionRequest {
    /// Shown in the selection toolbar, e.g. "1080p · 60 fps".
    let qualityBadge: String
}

@MainActor
protocol AreaSelecting: AnyObject {
    /// Shows the selection overlay on every display. Returns nil when cancelled (Esc / ✕).
    /// Space returns the full display under the cursor (`sourceRect == nil`).
    func selectArea(_ request: AreaSelectionRequest) async -> CaptureTarget?
}

@MainActor
protocol CountdownPresenting: AnyObject {
    /// Returns false when the user cancels (Esc). A click skips straight to true.
    func run(seconds: Int, target: CaptureTarget) async -> Bool
}

struct RecordingHUDActions {
    let pause: @MainActor () -> Void
    let resume: @MainActor () -> Void
    let stop: @MainActor () -> Void
    let discard: @MainActor () -> Void
}

@MainActor
protocol RecordingHUDPresenting: AnyObject {
    /// Shows the floating HUD and, for area captures, the red outline around the area.
    func show(for target: CaptureTarget, actions: RecordingHUDActions)
    func update(elapsed: TimeInterval, isPaused: Bool)
    func dismiss()
}

/// Concrete implementations, wired in `App/CompositionRoot.swift`.
@MainActor
struct AppDependencies {
    let recorder: ScreenRecording
    let meetingRecorder: MeetingRecording
    let areaSelector: AreaSelecting
    let countdown: CountdownPresenting
    let hud: RecordingHUDPresenting
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}
