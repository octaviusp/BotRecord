import Foundation
import os

/// The observer slot shared between the main actor (which sets it) and the audio queue (which reads it).
final class LiveAudioObserverSlot: @unchecked Sendable {
    private let observer = OSAllocatedUnfairLock<(any LiveAudioObserver)?>(initialState: nil)

    var current: (any LiveAudioObserver)? {
        get { observer.withLock { $0 } }
        set { observer.withLock { $0 = newValue } }
    }
}

/// Turns one track's committed 48 kHz audio into 16 kHz mono chunks for live transcription.
/// Fed with exactly what the file contains, so chunk times match the recording timeline.
/// Not thread-safe: confined to the capture queue that feeds it.
final class TranscriptionTap {
    static let sampleRate = 16_000
    /// 200 ms: short enough for a live transcript, long enough to keep observer calls cheap.
    private static let chunkSamples = sampleRate / 5

    private let track: MeetingTrack
    private let slot: LiveAudioObserverSlot
    private let resampler: MonoResampler
    private var pending: [Float] = []
    /// Timeline position of `pending[0]`.
    private var pendingStartTime: TimeInterval = 0

    init(track: MeetingTrack, slot: LiveAudioObserverSlot) throws {
        self.track = track
        self.slot = slot
        resampler = try MonoResampler(inputRate: Double(StereoPCMChunk.sampleRate), outputRate: Double(Self.sampleRate))
    }

    func consume(_ chunk: StereoPCMChunk) throws {
        guard let observer = slot.current else {
            pending.removeAll() // nobody listens: skip the work, times restart from the next chunk
            return
        }
        if pending.isEmpty { pendingStartTime = Double(chunk.startFrame) / Double(StereoPCMChunk.sampleRate) }
        pending.append(contentsOf: try resampler.resample(Self.mono(chunk.samples)))
        while pending.count >= Self.chunkSamples {
            emit(Array(pending.prefix(Self.chunkSamples)), to: observer)
            pending.removeFirst(Self.chunkSamples)
        }
    }

    /// Delivers the last partial chunk.
    func flush() {
        guard let observer = slot.current, !pending.isEmpty else { return }
        emit(pending, to: observer)
        pending.removeAll()
    }

    private func emit(_ samples: [Float], to observer: any LiveAudioObserver) {
        observer.liveAudio(samples, track: track, startTime: pendingStartTime)
        pendingStartTime += Double(samples.count) / Double(Self.sampleRate)
    }

    private static func mono(_ stereo: [Float]) -> [Float] {
        (0..<stereo.count / 2).map { (stereo[$0 * 2] + stereo[$0 * 2 + 1]) * 0.5 }
    }
}
