import Foundation

enum MeetingTrack: String, Codable, Sendable {
    /// The user's microphone.
    case me
    /// Everyone else: the sound of every app.
    case others
}

/// When the microphone runs through Apple's voice processing. It removes the call audio that speakers leak
/// into the mic, but lowers the call's own volume (~8 dB) and costs ~13% of a core, so Auto enables it only
/// when the sound comes out of the built-in speakers.
enum EchoCancellationMode: String, CaseIterable, Codable, Sendable {
    case auto, on, off

    var label: String { rawValue.capitalized }
}

struct MeetingOptions: Sendable {
    /// Records the "Me" track.
    var captureMicrophone: Bool
    /// Removes the call audio that leaks into the microphone; already resolved from `EchoCancellationMode`.
    var echoCancellation: Bool
    /// Also records the main display as video (with both voices mixed) next to the audio.
    var screen: RecordingOptions?
    /// Meeting folder created by the library; the recorder writes `audio.webm` (and `video.webm`) into it.
    var folder: URL
}

struct MeetingCaptureResult: Sendable {
    let folder: URL
    /// Two Opus tracks: "Me" and "Others".
    let audioURL: URL
    let videoURL: URL?
    let startedAt: Date
    let duration: TimeInterval
}

@MainActor
protocol MeetingRecording: AnyObject {
    var isPaused: Bool { get }
    /// Recorded time, excluding pauses.
    var elapsed: TimeInterval { get }
    var onFailure: ((RecordingFailure) -> Void)? { get set }
    /// Receives each track's audio for live transcription; set before `start`, cleared after `stop`.
    var audioObserver: LiveAudioObserver? { get set }

    func start(_ options: MeetingOptions) async throws
    func pause()
    func resume()
    func stop() async throws -> MeetingCaptureResult
    /// Discards the meeting's media files.
    func cancel() async
}
