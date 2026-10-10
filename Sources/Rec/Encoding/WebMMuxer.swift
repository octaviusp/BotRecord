import Foundation

/// Hand-written WebM writer: an optional AV1 video track plus any number of audio tracks.
///
/// Layout: EBML header, Segment { reserved SeekHead, Info, Tracks, Clusters…, Cues }.
/// Clusters are built in memory (≤ 5 s) and written with exact sizes; the Segment size,
/// Duration and SeekHead are patched in place by `finish()`. The Segment starts with an unknown
/// size, so a file cut short by a crash still plays up to its last written cluster.
/// Not thread-safe: the owner confines every call to one serial queue.
final class WebMMuxer: @unchecked Sendable {
    struct VideoTrack {
        let width: Int
        let height: Int
        /// `av1C` record.
        let codecPrivate: Data
        /// Duration assumed for the last frame when computing the file duration.
        let nominalFrameDurationMilliseconds: Int64
    }

    struct AudioTrack {
        /// Shown by players as the track title (e.g. "Me", "Others").
        let name: String?
        let codecID: String
        let codecPrivate: Data
        let codecDelayNanoseconds: UInt64
        let seekPreRollNanoseconds: UInt64
        let sampleRate: Double
        let channelCount: Int
    }

    private struct CuePoint {
        let timestamp: Int64
        let track: UInt8
        let clusterPosition: UInt64
    }

    private static let maxClusterDurationMilliseconds: Int64 = 5_000
    private static let reservedSeekHeadBytes = 128

    private let file: OutputFile
    private let video: VideoTrack?
    private let videoTrackNumber: UInt8 = 1
    /// Track number of each audio track, in the order given to `init`.
    private let audioTrackNumbers: [UInt8]
    private let segmentSizeOffset: UInt64
    private let segmentDataStart: UInt64
    private let seekHeadOffset: UInt64
    private let durationOffset: UInt64
    private let infoPosition: UInt64
    private let tracksPosition: UInt64

    private var cluster: Data?
    private var clusterTimestamp: Int64 = 0
    private var clusterHasVideo = false
    private var cuePoints: [CuePoint] = []
    /// Audio waits here until every pacing track has reached its timestamp, so blocks stay in time order.
    /// The video track paces when present; otherwise every audio track does.
    private var pendingAudio: [[EncodedAudioPacket]]
    private var lastAudioTimestamps: [Int64]
    private var lastVideoTimestamp: Int64 = -1
    private var endTimestamp: Int64 = 0

    init(url: URL, video: VideoTrack?, audio: [AudioTrack]) throws {
        precondition(video != nil || !audio.isEmpty, "a WebM file needs at least one track")
        precondition(audio.count < 126, "track numbers are written as 1-byte vints")
        self.video = video
        let firstAudioNumber: UInt8 = video == nil ? 1 : 2
        audioTrackNumbers = audio.indices.map { firstAudioNumber + UInt8($0) }
        pendingAudio = Array(repeating: [], count: audio.count)
        lastAudioTimestamps = Array(repeating: -1, count: audio.count)
        file = try OutputFile(url: url)

        try file.write(Self.ebmlHeader())
        try file.write(EBML.id(MatroskaID.segment))
        segmentSizeOffset = file.offset
        try file.write(EBML.unknownSize)
        segmentDataStart = file.offset

        seekHeadOffset = file.offset
        try file.write(EBML.void(totalBytes: Self.reservedSeekHeadBytes))

        infoPosition = file.offset - segmentDataStart
        try file.write(Self.info())
        // Duration is the Info's last child, so its 8-byte float payload ends the element.
        durationOffset = file.offset - 8

        tracksPosition = file.offset - segmentDataStart
        try file.write(Self.tracks(video: video, videoNumber: videoTrackNumber, audio: Array(zip(audio, audioTrackNumbers))))
    }

    func addVideo(_ packet: EncodedVideoPacket) throws {
        guard let video else { throw EncodingError.encoderFailure("video packet for a file without a video track") }
        try writeAudio(upTo: packet.ptsMilliseconds)
        let startsCluster = packet.isKeyframe
            && !(cluster != nil && !clusterHasVideo && clusterTimestamp == packet.ptsMilliseconds)
        if startsCluster { try openCluster(at: packet.ptsMilliseconds) }
        if packet.isKeyframe {
            cuePoints.append(CuePoint(timestamp: packet.ptsMilliseconds, track: videoTrackNumber,
                                      clusterPosition: clusterStartPosition))
        }
        try appendBlock(track: videoTrackNumber, timestamp: packet.ptsMilliseconds,
                        isKeyframe: packet.isKeyframe, payload: packet.data)
        clusterHasVideo = true
        lastVideoTimestamp = packet.ptsMilliseconds
        endTimestamp = max(endTimestamp, packet.ptsMilliseconds + video.nominalFrameDurationMilliseconds)
    }

    /// - Parameter trackIndex: position of the track in the `audio` array given to `init`.
    func addAudio(_ packet: EncodedAudioPacket, trackIndex: Int) throws {
        pendingAudio[trackIndex].append(packet)
        lastAudioTimestamps[trackIndex] = packet.ptsMilliseconds
        try writeAudio(upTo: video == nil ? lastAudioTimestamps.min() ?? -1 : lastVideoTimestamp)
    }

    /// Writes buffered blocks, Cues, SeekHead, Duration and Segment size, then closes the file.
    func finish() throws {
        try writeAudio(upTo: .max)
        try closeCluster()

        let cuesPosition = file.offset - segmentDataStart
        try file.write(cues())
        let segmentEnd = file.offset

        try file.write(EBML.fixedSize(Int(segmentEnd - segmentDataStart)), at: segmentSizeOffset)
        try file.write(seekHead(cuesPosition: cuesPosition), at: seekHeadOffset)
        let duration = withUnsafeBytes(of: Double(endTimestamp).bitPattern.bigEndian) { Data($0) }
        try file.write(duration, at: durationOffset)
        try file.close()
    }

    /// Closes and deletes the partial file.
    func abort() {
        file.discard()
    }

    // MARK: - Clusters

    private var clusterStartPosition: UInt64 { file.offset - segmentDataStart }

    /// Merges the audio queues in timestamp order, up to and including `timestamp`.
    private func writeAudio(upTo timestamp: Int64) throws {
        var heads = Array(repeating: 0, count: pendingAudio.count)
        while let index = nextAudioTrack(heads: heads, limit: timestamp) {
            let packet = pendingAudio[index][heads[index]]
            try appendBlock(track: audioTrackNumbers[index], timestamp: packet.ptsMilliseconds,
                            isKeyframe: true, payload: packet.data)
            endTimestamp = max(endTimestamp, packet.ptsMilliseconds + packet.durationMilliseconds)
            heads[index] += 1
        }
        for index in heads.indices where heads[index] > 0 { pendingAudio[index].removeFirst(heads[index]) }
    }

    private func nextAudioTrack(heads: [Int], limit: Int64) -> Int? {
        var best: (index: Int, timestamp: Int64)?
        for index in pendingAudio.indices where heads[index] < pendingAudio[index].count {
            let timestamp = pendingAudio[index][heads[index]].ptsMilliseconds
            if timestamp <= limit, timestamp < best?.timestamp ?? .max { best = (index, timestamp) }
        }
        return best?.index
    }

    private func appendBlock(track: UInt8, timestamp: Int64, isKeyframe: Bool, payload: Data) throws {
        if cluster == nil || timestamp - clusterTimestamp >= Self.maxClusterDurationMilliseconds {
            try openCluster(at: timestamp)
            // Without video every cluster starts with an Opus block, which is always a seek point.
            if video == nil {
                cuePoints.append(CuePoint(timestamp: timestamp, track: track, clusterPosition: clusterStartPosition))
            }
        }
        let relative = Int16(timestamp - clusterTimestamp)
        var block = Data([0x80 | track]) // track number as a 1-byte vint
        withUnsafeBytes(of: relative.bigEndian) { block.append(contentsOf: $0) }
        block.append(isKeyframe ? 0x80 : 0x00)
        block.append(payload)
        cluster?.append(EBML.element(MatroskaID.simpleBlock, block))
    }

    private func openCluster(at timestamp: Int64) throws {
        try closeCluster()
        cluster = EBML.unsigned(MatroskaID.timestamp, UInt64(timestamp))
        clusterTimestamp = timestamp
        clusterHasVideo = false
    }

    private func closeCluster() throws {
        guard let body = cluster else { return }
        try file.write(EBML.element(MatroskaID.cluster, body))
        cluster = nil
    }

    // MARK: - Fixed elements

    private func cues() -> Data {
        EBML.master(MatroskaID.cues, cuePoints.map { point in
            EBML.master(MatroskaID.cuePoint, [
                EBML.unsigned(MatroskaID.cueTime, UInt64(point.timestamp)),
                EBML.master(MatroskaID.cueTrackPositions, [
                    EBML.unsigned(MatroskaID.cueTrack, UInt64(point.track)),
                    EBML.unsigned(MatroskaID.cueClusterPosition, point.clusterPosition),
                ]),
            ])
        })
    }

    private func seekHead(cuesPosition: UInt64) -> Data {
        let entries: [(UInt32, UInt64)] = [
            (MatroskaID.info, infoPosition),
            (MatroskaID.tracks, tracksPosition),
            (MatroskaID.cues, cuesPosition),
        ]
        let seekHead = EBML.master(MatroskaID.seekHead, entries.map { id, position in
            EBML.master(MatroskaID.seek, [
                EBML.element(MatroskaID.seekID, EBML.id(id)),
                EBML.unsigned(MatroskaID.seekPosition, position),
            ])
        })
        var reserved = seekHead
        reserved.append(EBML.void(totalBytes: Self.reservedSeekHeadBytes - seekHead.count))
        return reserved
    }

    private static func ebmlHeader() -> Data {
        EBML.master(MatroskaID.ebml, [
            EBML.unsigned(MatroskaID.ebmlVersion, 1),
            EBML.unsigned(MatroskaID.ebmlReadVersion, 1),
            EBML.unsigned(MatroskaID.ebmlMaxIDLength, 4),
            EBML.unsigned(MatroskaID.ebmlMaxSizeLength, 8),
            EBML.string(MatroskaID.docType, "webm"),
            EBML.unsigned(MatroskaID.docTypeVersion, 4),
            EBML.unsigned(MatroskaID.docTypeReadVersion, 2),
        ])
    }

    private static func info() -> Data {
        EBML.master(MatroskaID.info, [
            EBML.unsigned(MatroskaID.timestampScale, 1_000_000), // 1 ms ticks
            EBML.string(MatroskaID.muxingApp, "Rec"),
            EBML.string(MatroskaID.writingApp, "Rec"),
            EBML.float(MatroskaID.duration, 0), // patched by finish()
        ])
    }

    private static func tracks(video: VideoTrack?, videoNumber: UInt8, audio: [(AudioTrack, UInt8)]) -> Data {
        var entries = video.map { [videoEntry($0, number: videoNumber)] } ?? []
        entries += audio.map { track, number in audioEntry(track, number: number) }
        return EBML.master(MatroskaID.tracks, entries)
    }

    private static func videoEntry(_ video: VideoTrack, number: UInt8) -> Data {
        EBML.master(MatroskaID.trackEntry, [
            EBML.unsigned(MatroskaID.trackNumber, UInt64(number)),
            EBML.unsigned(MatroskaID.trackUID, UInt64.random(in: 1...UInt64.max)),
            EBML.unsigned(MatroskaID.trackType, 1),
            EBML.unsigned(MatroskaID.flagLacing, 0),
            EBML.string(MatroskaID.codecID, "V_AV1"),
            EBML.element(MatroskaID.codecPrivate, video.codecPrivate),
            EBML.master(MatroskaID.video, [
                EBML.unsigned(MatroskaID.pixelWidth, UInt64(video.width)),
                EBML.unsigned(MatroskaID.pixelHeight, UInt64(video.height)),
                // BT.709, limited range: matches the encoder's sequence header.
                EBML.master(MatroskaID.colour, [
                    EBML.unsigned(MatroskaID.matrixCoefficients, 1),
                    EBML.unsigned(MatroskaID.range, 1),
                    EBML.unsigned(MatroskaID.transferCharacteristics, 1),
                    EBML.unsigned(MatroskaID.primaries, 1),
                ]),
            ]),
        ])
    }

    private static func audioEntry(_ track: AudioTrack, number: UInt8) -> Data {
        var children = [
            EBML.unsigned(MatroskaID.trackNumber, UInt64(number)),
            EBML.unsigned(MatroskaID.trackUID, UInt64.random(in: 1...UInt64.max)),
            EBML.unsigned(MatroskaID.trackType, 2),
            EBML.unsigned(MatroskaID.flagLacing, 0),
        ]
        if let name = track.name { children.append(EBML.string(MatroskaID.name, name)) }
        children += [
            EBML.string(MatroskaID.codecID, track.codecID),
            EBML.element(MatroskaID.codecPrivate, track.codecPrivate),
            EBML.unsigned(MatroskaID.codecDelay, track.codecDelayNanoseconds),
            EBML.unsigned(MatroskaID.seekPreRoll, track.seekPreRollNanoseconds),
            EBML.master(MatroskaID.audio, [
                EBML.float(MatroskaID.samplingFrequency, track.sampleRate),
                EBML.unsigned(MatroskaID.channels, UInt64(track.channelCount)),
            ]),
        ]
        return EBML.master(MatroskaID.trackEntry, children)
    }
}
