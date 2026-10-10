import Foundation

/// Audio-only WebM with one Opus track per independent source (e.g. "Me" and "Others").
///
/// Each source is aligned on the shared recording timeline before encoding: gaps become silence
/// and late overlaps are dropped, so every track is gapless from frame 0 and tracks stay in sync.
/// Not thread-safe: the owner confines every call to one serial queue.
final class MultiTrackAudioWriter {
    struct Track {
        let name: String
        let opus: OpusAudioEncoder.Settings
    }

    private struct TrackState {
        /// A one-source mixer is exactly a gap-filling aligner; the source key is arbitrary.
        let aligner = AudioMixer(sources: [alignerSource])
        let encoder: OpusAudioEncoder
    }

    private static let alignerSource = AudioSource.system

    let url: URL
    private let muxer: WebMMuxer
    private let tracks: [TrackState]

    init(url: URL, tracks: [Track]) throws {
        precondition(!tracks.isEmpty, "an audio file needs at least one track")
        let states = try tracks.map { TrackState(encoder: try OpusAudioEncoder($0.opus)) }
        muxer = try WebMMuxer(url: url, video: nil,
                              audio: zip(tracks, states).map { track, state in state.encoder.webMTrack(named: track.name) })
        self.url = url
        self.tracks = states
    }

    /// Adds audio positioned on the timeline. Returns the audio newly committed to the track
    /// (gapless, may differ from the input), for consumers that must match the file exactly.
    func append(_ chunk: StereoPCMChunk, toTrack index: Int) throws -> StereoPCMChunk? {
        tracks[index].aligner.append(chunk, from: Self.alignerSource)
        return try commit(tracks[index].aligner.drain(), track: index)
    }

    /// Fills every track that has not reached `frame` with silence (a silent app sends nothing),
    /// so tracks keep interleaving and memory stays flat. Returns the committed audio per track.
    func advance(to frame: Int64) throws -> [StereoPCMChunk?] {
        try tracks.indices.map { try commit(tracks[$0].aligner.advance(to: frame), track: $0) }
    }

    /// Encodes the tails and finalizes the file. Returns each track's last committed audio.
    func finish() throws -> [StereoPCMChunk?] {
        let tails = try tracks.indices.map { index -> StereoPCMChunk? in
            let tail = try commit(tracks[index].aligner.flush(), track: index)
            for packet in try tracks[index].encoder.flush() { try muxer.addAudio(packet, trackIndex: index) }
            return tail
        }
        try muxer.finish()
        return tails
    }

    /// Stops without finalizing and deletes the file.
    func cancel() {
        muxer.abort()
    }

    private func commit(_ chunk: StereoPCMChunk?, track index: Int) throws -> StereoPCMChunk? {
        guard let chunk else { return nil }
        for packet in try tracks[index].encoder.encode(chunk) { try muxer.addAudio(packet, trackIndex: index) }
        return chunk
    }
}
