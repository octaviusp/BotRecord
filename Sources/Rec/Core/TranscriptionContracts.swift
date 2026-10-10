import Foundation

/// Receives live 16 kHz mono Float32 audio per track for streaming transcription, from meetings and
/// screen recordings alike. Called from a capture queue, never the main thread; must return quickly.
protocol LiveAudioObserver: AnyObject, Sendable {
    /// `startTime` is the chunk's position on the recording timeline (seconds, pauses excluded).
    func liveAudio(_ samples: [Float], track: MeetingTrack, startTime: TimeInterval)
}

/// One recognized utterance; the transcript files are lists of these.
struct TranscriptSegment: Codable, Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let track: MeetingTrack
    let text: String
}

/// Handle of one utterance being recognized.
struct UtteranceID: Hashable, Sendable {
    let rawValue: UInt64
}

/// Speech recognition one utterance at a time; several utterances (one per track) may be open at once.
/// Audio is 16 kHz mono Float32. Implemented by `TranscriptionEngine` (Nemotron on MLX).
protocol SpeechTranscribing: Sendable {
    /// Loads and warms the model ahead of need, so the first utterance isn't delayed.
    func prepare() async throws
    /// - Parameters:
    ///   - language: BCP-47 tag the model supports, e.g. "es-US".
    ///   - leadIn: audio just before the speech onset (up to 320 ms), which primes the recognizer.
    func beginUtterance(language: String, leadIn: [Float]) async throws -> UtteranceID
    func append(_ samples: [Float], to utterance: UtteranceID) async throws
    /// Ends the utterance and returns its text, empty when nothing was recognized.
    func finishUtterance(_ utterance: UtteranceID) async throws -> String
    /// Drops an open utterance without recognizing the rest.
    func discardUtterance(_ utterance: UtteranceID) async
}

/// Where a transcript is persisted; rewritten as a whole after each new segment, so it is crash-safe.
protocol TranscriptOutput: Sendable {
    /// Segments arrive sorted by start time.
    func write(_ segments: [TranscriptSegment]) throws
}
