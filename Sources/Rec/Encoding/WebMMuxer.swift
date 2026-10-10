import Foundation

/// Hand-written WebM writer: one AV1 video track and an optional Opus track.
///
/// Layout: EBML header, Segment { reserved SeekHead, Info, Tracks, Clusters…, Cues }.
/// Clusters are built in memory (≤ 5 s) and written with exact sizes; the Segment size,
/// Duration and SeekHead are patched in place by `finish()`.
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

    private static let videoTrackNumber: UInt8 = 1
    private static let audioTrackNumber: UInt8 = 2
    private static let maxClusterDurationMilliseconds: Int64 = 5_000
    private static let reservedSeekHeadBytes = 128

    private let file: OutputFile
    private let video: VideoTrack
    private let segmentSizeOffset: UInt64
    private let segmentDataStart: UInt64
    private let seekHeadOffset: UInt64
    private let durationOffset: UInt64
    private let infoPosition: UInt64
    private let tracksPosition: UInt64

    private var cluster: Data?
    private var clusterTimestamp: Int64 = 0
    private var clusterHasVideo = false
    private var cuePoints: [(timestamp: Int64, clusterPosition: UInt64)] = []
    /// Audio waits here until video has reached its timestamp, so blocks stay in time order.
    private var pendingAudio: [EncodedAudioPacket] = []
    private var lastVideoTimestamp: Int64 = -1
    private var endTimestamp: Int64 = 0

    init(url: URL, video: VideoTrack, includesAudio: Bool) throws {
        self.video = video
        file = try OutputFile(url: url)

        try file.write(Self.ebmlHeader())
        try file.write(EBML.id(MatroskaID.segment))
        segmentSizeOffset = file.offset
        try file.write(EBML.unknownSize)
        segmentDataStart = file.offset

        seekHeadOffset = file.offset
        try file.write(EBML.void(totalBytes: Self.reservedSeekHeadBytes))

        infoPosition = file.offset - segmentDataStart
        let info = Self.info()
        try file.write(info)
        // Duration is the Info's last child, so its 8-byte float payload ends the element.
        durationOffset = file.offset - 8

        tracksPosition = file.offset - segmentDataStart
        try file.write(Self.tracks(video: video, includesAudio: includesAudio))
    }

    func addVideo(_ packet: EncodedVideoPacket) throws {
        try writeAudio(upTo: packet.ptsMilliseconds)
        let startsCluster = packet.isKeyframe
            && !(cluster != nil && !clusterHasVideo && clusterTimestamp == packet.ptsMilliseconds)
        if startsCluster { try openCluster(at: packet.ptsMilliseconds) }
        if packet.isKeyframe {
            cuePoints.append((packet.ptsMilliseconds, clusterStartPosition))
        }
        try appendBlock(track: Self.videoTrackNumber, timestamp: packet.ptsMilliseconds,
                        isKeyframe: packet.isKeyframe, payload: packet.data)
        clusterHasVideo = true
        lastVideoTimestamp = packet.ptsMilliseconds
        endTimestamp = max(endTimestamp, packet.ptsMilliseconds + video.nominalFrameDurationMilliseconds)
    }

    func addAudio(_ packet: EncodedAudioPacket) throws {
        pendingAudio.append(packet)
        try writeAudio(upTo: lastVideoTimestamp)
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

    private func writeAudio(upTo timestamp: Int64) throws {
        var written = 0
        for packet in pendingAudio {
            guard packet.ptsMilliseconds <= timestamp else { break }
            try appendBlock(track: Self.audioTrackNumber, timestamp: packet.ptsMilliseconds,
                            isKeyframe: true, payload: packet.data)
            endTimestamp = max(endTimestamp, packet.ptsMilliseconds + packet.durationMilliseconds)
            written += 1
        }
        pendingAudio.removeFirst(written)
    }

    private func appendBlock(track: UInt8, timestamp: Int64, isKeyframe: Bool, payload: Data) throws {
        if cluster == nil || timestamp - clusterTimestamp >= Self.maxClusterDurationMilliseconds {
            try openCluster(at: timestamp)
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
                    EBML.unsigned(MatroskaID.cueTrack, UInt64(Self.videoTrackNumber)),
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

    private static func tracks(video: VideoTrack, includesAudio: Bool) -> Data {
        var entries = [
            EBML.master(MatroskaID.trackEntry, [
                EBML.unsigned(MatroskaID.trackNumber, UInt64(videoTrackNumber)),
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
            ]),
        ]
        if includesAudio {
            entries.append(EBML.master(MatroskaID.trackEntry, [
                EBML.unsigned(MatroskaID.trackNumber, UInt64(audioTrackNumber)),
                EBML.unsigned(MatroskaID.trackUID, UInt64.random(in: 1...UInt64.max)),
                EBML.unsigned(MatroskaID.trackType, 2),
                EBML.unsigned(MatroskaID.flagLacing, 0),
                EBML.string(MatroskaID.codecID, "A_OPUS"),
                EBML.element(MatroskaID.codecPrivate, OpusAudioEncoder.identificationHeader),
                EBML.unsigned(MatroskaID.codecDelay, OpusAudioEncoder.codecDelayNanoseconds),
                EBML.unsigned(MatroskaID.seekPreRoll, OpusAudioEncoder.seekPreRollNanoseconds),
                EBML.master(MatroskaID.audio, [
                    EBML.float(MatroskaID.samplingFrequency, Double(OpusAudioEncoder.sampleRate)),
                    EBML.unsigned(MatroskaID.channels, UInt64(OpusAudioEncoder.channelCount)),
                ]),
            ]))
        }
        return EBML.master(MatroskaID.tracks, entries)
    }
}
