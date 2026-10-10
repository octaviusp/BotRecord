import Accelerate
import Foundation

/// Splits one track's 16 kHz mono stream into utterances with a simple energy VAD, so each utterance
/// gets its own recognizer session and becomes one transcript segment.
///
/// Works on 20 ms frames: a frame is speech when it is `marginDB` above a tracked noise floor (and above
/// an absolute minimum). Three speech frames in a row start an utterance; `hangover` of silence ends it.
/// Not thread-safe: owned by one track's worker.
struct SpeechSegmenter {
    enum Event: Equatable {
        /// Speech started at `onset`; `leadIn` is the audio just before it (up to `leadInSamples`).
        case began(onset: TimeInterval, leadIn: [Float])
        /// More audio of the open utterance, pauses included.
        case audio([Float])
        /// The open utterance ended; `at` is the end of its last speech frame.
        case ended(at: TimeInterval)
    }

    static let sampleRate = 16_000
    /// 320 ms: what the recognizer needs before the first word (see `TranscriptionEngine`).
    static let leadInSamples = 5_120
    private static let frameSamples = 320
    private static let onsetFrames = 3
    /// 700 ms of silence ends an utterance: longer than a pause between words, shorter than a turn change.
    private static let hangoverFrames = 35
    /// Long monologues are cut so segments keep streaming to disk and timestamps stay useful.
    private static let maxUtteranceSeconds: TimeInterval = 30
    /// Quieter than this is never speech, whatever the noise floor (digital silence sits far below).
    private static let minimumSpeechDB: Float = -50
    private static let marginDB: Float = 12
    private static let floorLimitDB: Float = -90
    /// The floor drops instantly to any quieter frame and creeps up 1 dB/s, so it follows the room noise
    /// without climbing into speech: the dips between words keep pulling it back down.
    private static let floorRisePerFrameDB: Float = 0.02
    /// A jump in chunk times beyond this (dropped chunks, paused taps) restarts segmentation.
    private static let discontinuityTolerance: TimeInterval = 0.05

    private var noiseFloorDB: Float = -60
    /// Samples not yet forming a whole frame, and the timeline position of the first of them.
    private var leftover: [Float] = []
    private var leftoverStart: TimeInterval?
    /// The most recent audio: the lead-in for the next onset, plus the onset frames themselves.
    private var recent: [Float] = []
    private var onsetCount = 0
    private var utterance: (start: TimeInterval, lastSpeechEnd: TimeInterval, silentFrames: Int)?

    mutating func process(_ samples: [Float], startTime: TimeInterval) -> [Event] {
        var events: [Event] = []
        if let expected = leftoverStart.map({ $0 + Self.seconds(leftover.count) }),
           abs(startTime - expected) > Self.discontinuityTolerance {
            events += closeUtterance()
            leftover.removeAll()
            recent.removeAll()
            onsetCount = 0
        }
        if leftover.isEmpty { leftoverStart = startTime }
        leftover += samples

        var audio: [Float] = []
        var offset = 0
        while leftover.count - offset >= Self.frameSamples {
            let frame = Array(leftover[offset..<(offset + Self.frameSamples)])
            let frameStart = (leftoverStart ?? startTime) + Self.seconds(offset)
            offset += Self.frameSamples
            events += consume(frame, at: frameStart, audio: &audio)
        }
        if !audio.isEmpty { events.append(.audio(audio)) }
        leftover.removeFirst(offset)
        leftoverStart = leftoverStart.map { $0 + Self.seconds(offset) }
        return events
    }

    /// Ends the open utterance, if any, at the end of the stream.
    mutating func finish() -> [Event] {
        var events: [Event] = []
        if utterance != nil, !leftover.isEmpty { events.append(.audio(leftover)) }
        leftover.removeAll()
        return events + closeUtterance()
    }

    // MARK: Frames

    private mutating func consume(_ frame: [Float], at start: TimeInterval, audio: inout [Float]) -> [Event] {
        let isSpeech = classify(frame)
        let end = start + Self.seconds(frame.count)
        remember(frame)
        guard var open = utterance else { return idleFrame(isSpeech: isSpeech, end: end) }

        audio += frame
        if isSpeech {
            open.lastSpeechEnd = end
            open.silentFrames = 0
        } else {
            open.silentFrames += 1
        }
        utterance = open
        let endsInSilence = open.silentFrames >= Self.hangoverFrames
        guard endsInSilence || end - open.start >= Self.maxUtteranceSeconds else { return [] }

        let events: [Event] = [.audio(audio), .ended(at: endsInSilence ? open.lastSpeechEnd : end)]
        audio.removeAll()
        utterance = nil
        // After a forced cut the recent audio is speech already transcribed: priming with it would repeat words.
        if !endsInSilence { recent.removeAll() }
        return events
    }

    private mutating func idleFrame(isSpeech: Bool, end: TimeInterval) -> [Event] {
        onsetCount = isSpeech ? onsetCount + 1 : 0
        guard onsetCount >= Self.onsetFrames else { return [] }

        let onsetSamples = onsetCount * Self.frameSamples
        let leadIn = Array(recent.dropLast(onsetSamples).suffix(Self.leadInSamples))
        let speech = Array(recent.suffix(onsetSamples))
        let onset = end - Self.seconds(onsetSamples)
        onsetCount = 0
        utterance = (start: onset, lastSpeechEnd: end, silentFrames: 0)
        return [.began(onset: onset, leadIn: leadIn), .audio(speech)]
    }

    /// Keeps the last lead-in plus a pending onset worth of audio.
    private mutating func remember(_ frame: [Float]) {
        recent += frame
        let keep = Self.leadInSamples + Self.onsetFrames * Self.frameSamples
        if recent.count > keep { recent.removeFirst(recent.count - keep) }
    }

    private mutating func closeUtterance() -> [Event] {
        guard let open = utterance else { return [] }
        utterance = nil
        return [.ended(at: open.lastSpeechEnd)]
    }

    /// Updates the noise floor and says whether the frame is speech.
    private mutating func classify(_ frame: [Float]) -> Bool {
        var meanSquare: Float = 0
        vDSP_measqv(frame, 1, &meanSquare, vDSP_Length(frame.count))
        let level = max(10 * log10(meanSquare + 1e-12), Self.floorLimitDB)
        let isSpeech = level > max(Self.minimumSpeechDB, noiseFloorDB + Self.marginDB)
        noiseFloorDB = level < noiseFloorDB ? level : noiseFloorDB + Self.floorRisePerFrameDB
        return isSpeech
    }

    private static func seconds(_ samples: Int) -> TimeInterval {
        Double(samples) / Double(sampleRate)
    }
}
