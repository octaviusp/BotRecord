import Foundation
import os

/// Gathers the segments of every track in time order and rewrites the output after each one,
/// so a crash mid-recording loses at most the utterance in flight.
actor TranscriptCollector {
    private var segments: [TranscriptSegment] = []
    private var output: TranscriptOutput?
    private var firstError: Error?
    private let logger = Logger(subsystem: AppPaths.identifier, category: "transcription")

    init(output: TranscriptOutput?) {
        self.output = output
    }

    func add(_ segment: TranscriptSegment) {
        // Tracks finish utterances independently, so a segment may start before the last one stored.
        let index = segments.lastIndex { $0.start <= segment.start }.map { $0 + 1 } ?? 0
        segments.insert(segment, at: index)
        persist()
    }

    func attach(_ output: TranscriptOutput) {
        self.output = output
        if !segments.isEmpty { persist() }
    }

    func fail(_ error: Error) {
        logger.error("Transcription failed: \(error.localizedDescription)")
        if firstError == nil { firstError = error }
    }

    /// Writes the final transcript, even an empty one, so its presence says transcription ran.
    func complete(droppedSeconds: TimeInterval) -> LiveTranscriber.Outcome {
        persist()
        if droppedSeconds > 0 {
            logger.error("Transcription fell behind and skipped \(droppedSeconds, format: .fixed(precision: 1)) s of audio")
        }
        return LiveTranscriber.Outcome(segments: segments, error: firstError, droppedSeconds: droppedSeconds)
    }

    private func persist() {
        guard let output else { return }
        do {
            try output.write(segments)
        } catch {
            fail(error)
        }
    }
}
