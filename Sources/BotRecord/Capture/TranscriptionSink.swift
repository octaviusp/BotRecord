import CoreMedia
import CoreVideo

/// Feeds a screen recording's audio to live transcription: every source mixed into one stream on the
/// recording timeline (a recording has one narrator; separate mic and system tracks would transcribe the
/// speakers' echo twice), down to 16 kHz mono chunks. Runs on the capture queue like any sink.
///
/// Transcription is a convenience: an error here disables it and is logged, never stopping the recording.
final class TranscriptionSink: MediaSink {
    private let pipeline: MixedAudioPipeline
    private let tap: TranscriptionTap
    private var isFailed = false

    init(sources: Set<AudioSource>, observer: LiveAudioObserver) throws {
        pipeline = MixedAudioPipeline(sources: sources)
        let slot = LiveAudioObserverSlot()
        slot.current = observer
        // The track only labels segments; recordings write captions without speakers.
        tap = try TranscriptionTap(track: sources.contains(.system) ? .others : .me, slot: slot)
    }

    func appendVideo(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) throws {}

    func appendAudio(_ sampleBuffer: CMSampleBuffer, source: AudioSource) throws {
        guard !isFailed else { return }
        transcribing { if let mixed = try pipeline.process(sampleBuffer, from: source) { try tap.consume(mixed) } }
    }

    /// Call once the capture queue is drained: delivers the mix's tail and the last partial chunk.
    func finish() async {
        guard !isFailed else { return }
        transcribing {
            if let tail = pipeline.flush() { try tap.consume(tail) }
            tap.flush()
        }
    }

    func cancel() {
        isFailed = true
    }

    private func transcribing(_ step: () throws -> Void) {
        do {
            try step()
        } catch {
            isFailed = true
            captureLog.error("Transcription audio failed; the recording continues without a transcript: \(error.localizedDescription)")
        }
    }
}
