import Foundation

/// Aligns one or more stereo sources on the recording timeline and sums them.
/// Output is contiguous from frame 0, so the encoder never sees gaps.
final class AudioMixer {
    /// Jitter tolerated before a timestamp jump is treated as a gap (10 ms).
    private static let jitterToleranceFrames: Int64 = 480
    /// Default lag tolerance (100 ms): ScreenCaptureKit delivers all its sources with similar latency.
    static let defaultMaxLagFrames: Int64 = 4_800

    private final class Track {
        var samples: [Float] = []
        /// Timeline frame of `samples[0]`.
        var startFrame: Int64 = 0
        var endFrame: Int64 { startFrame + Int64(samples.count / 2) }

        func appendSilence(frames: Int64) {
            guard frames > 0 else { return }
            samples.append(contentsOf: repeatElement(0, count: Int(frames) * 2))
        }
    }

    /// A source this far behind the leader is padded with silence so the mix keeps flowing.
    private let maxLagFrames: Int64
    private var tracks: [AudioSource: Track] = [:]
    /// Everything before this frame has been emitted.
    private var mixedUntilFrame: Int64 = 0

    init(sources: Set<AudioSource>, maxLagFrames: Int64 = defaultMaxLagFrames) {
        self.maxLagFrames = maxLagFrames
        for source in sources { tracks[source] = Track() }
    }

    func append(_ chunk: StereoPCMChunk, from source: AudioSource) {
        guard let track = tracks[source] else { return }
        let offset = chunk.startFrame - track.endFrame
        if offset > Self.jitterToleranceFrames {
            track.appendSilence(frames: offset)
            track.samples.append(contentsOf: chunk.samples)
        } else if offset < -Self.jitterToleranceFrames {
            // Late data for time already padded or mixed: drop the overlap to stay in sync.
            let overlap = Int(min(-offset, Int64(chunk.frameCount)))
            track.samples.append(contentsOf: chunk.samples[(overlap * 2)...])
        } else {
            track.samples.append(contentsOf: chunk.samples)
        }
    }

    /// Mixes every frame that all sources have reached.
    func drain() -> StereoPCMChunk? {
        guard let leaderEnd = tracks.values.map(\.endFrame).max() else { return nil }
        for track in tracks.values where track.endFrame < leaderEnd - maxLagFrames {
            track.appendSilence(frames: leaderEnd - maxLagFrames - track.endFrame)
        }
        let readyUntil = tracks.values.map(\.endFrame).min() ?? mixedUntilFrame
        return mix(until: readyUntil)
    }

    /// Pads every source that has not reached `frame` with silence and mixes up to it. Lets the output
    /// keep flowing when a source delivers nothing (ScreenCaptureKit sends no buffers while apps are
    /// silent); later data for padded time is dropped as late, so `frame` must trail real delivery.
    func advance(to frame: Int64) -> StereoPCMChunk? {
        for track in tracks.values { track.appendSilence(frames: frame - track.endFrame) }
        return drain()
    }

    /// Pads every source to the longest one and mixes the rest. Call once at the end.
    func flush() -> StereoPCMChunk? {
        guard let leaderEnd = tracks.values.map(\.endFrame).max() else { return nil }
        for track in tracks.values { track.appendSilence(frames: leaderEnd - track.endFrame) }
        return mix(until: leaderEnd)
    }

    private func mix(until endFrame: Int64) -> StereoPCMChunk? {
        let frameCount = Int(endFrame - mixedUntilFrame)
        guard frameCount > 0 else { return nil }
        var mixed = [Float](repeating: 0, count: frameCount * 2)
        for track in tracks.values {
            let skip = Int(mixedUntilFrame - track.startFrame) * 2
            for index in 0..<mixed.count { mixed[index] += track.samples[skip + index] }
            track.samples.removeFirst(skip + mixed.count)
            track.startFrame = endFrame
        }
        if tracks.count > 1 {
            for index in mixed.indices { mixed[index] = min(max(mixed[index], -1), 1) }
        }
        let chunk = StereoPCMChunk(samples: mixed, startFrame: mixedUntilFrame)
        mixedUntilFrame = endFrame
        return chunk
    }
}
