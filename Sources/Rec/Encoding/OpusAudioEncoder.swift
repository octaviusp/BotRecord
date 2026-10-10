import COpus
import Foundation

struct EncodedAudioPacket {
    let data: Data
    let ptsMilliseconds: Int64
    let durationMilliseconds: Int64
}

/// libopus wrapper: 48 kHz, mono or stereo, 20 ms frames. Input is always `StereoPCMChunk`;
/// a mono encoder averages both sides.
final class OpusAudioEncoder {
    struct Settings {
        let channelCount: Int32
        let bitsPerSecond: Int32
        /// `OPUS_APPLICATION_AUDIO` or `OPUS_APPLICATION_VOIP`; both share the 312-frame lookahead below.
        let application: Int32

        /// Transparent for speech and system sounds in a screen recording.
        static let screenRecording = Settings(channelCount: 2, bitsPerSecond: 96_000, application: OPUS_APPLICATION_AUDIO)
        /// One voice from a microphone: Opus' speech mode is near-transparent at 24 kb/s mono.
        static let voice = Settings(channelCount: 1, bitsPerSecond: 24_000, application: OPUS_APPLICATION_VOIP)
        /// Call audio that was already compressed by the call app; together with `voice` ≈ 25 MB/hour.
        static let callAudio = Settings(channelCount: 2, bitsPerSecond: 32_000, application: OPUS_APPLICATION_AUDIO)
    }

    static let sampleRate: Int32 = 48_000
    static let frameSize = 960 // 20 ms at 48 kHz
    /// libopus' encoder lookahead for the AUDIO and VOIP applications at 48 kHz (Fs/400 + Fs/250).
    /// Hard-coded because `opus_encoder_ctl(OPUS_GET_LOOKAHEAD)` is variadic and Swift can't call it.
    static let preSkipFrames: UInt16 = 312
    static let seekPreRollNanoseconds: UInt64 = 80_000_000
    static var codecDelayNanoseconds: UInt64 { UInt64(preSkipFrames) * 1_000_000_000 / UInt64(sampleRate) }

    let channelCount: Int32

    /// RFC 7845 §5.1 identification header, used as WebM CodecPrivate.
    var identificationHeader: Data {
        var header = Data("OpusHead".utf8)
        header.append(1) // version
        header.append(UInt8(channelCount))
        withUnsafeBytes(of: Self.preSkipFrames.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(Self.sampleRate).littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0, 0]) // output gain
        header.append(0) // channel mapping family 0 (mono/stereo)
        return header
    }

    private let encoder: OpaquePointer
    /// Samples (interleaved when stereo) not yet encoded. The input is gapless, so the
    /// timeline only needs the position of the first pending frame.
    private var pending: [Float] = []
    private var pendingStartFrame: Int64 = 0
    private var outputBuffer = [UInt8](repeating: 0, count: 4_000)

    init(_ settings: Settings = .screenRecording) throws {
        precondition(settings.channelCount == 1 || settings.channelCount == 2, "Opus mapping family 0 is mono or stereo")
        var status: Int32 = OPUS_OK
        guard let encoder = opus_encoder_create(Self.sampleRate, settings.channelCount, settings.application, &status),
              status == OPUS_OK
        else { throw EncodingError.encoderSetup("opus_encoder_create failed (\(Self.describe(status)))") }
        let bitrateStatus = rec_opus_set_bitrate(encoder, settings.bitsPerSecond)
        guard bitrateStatus == OPUS_OK else {
            opus_encoder_destroy(encoder)
            throw EncodingError.encoderSetup("Opus bitrate setup failed (\(Self.describe(bitrateStatus)))")
        }
        self.encoder = encoder
        channelCount = settings.channelCount
    }

    deinit { opus_encoder_destroy(encoder) }

    /// Encodes every complete 20 ms frame; the remainder waits for more audio.
    func encode(_ chunk: StereoPCMChunk) throws -> [EncodedAudioPacket] {
        if pending.isEmpty { pendingStartFrame = chunk.startFrame }
        appendToPending(chunk.samples)
        let samplesPerFrame = Self.frameSize * Int(channelCount)
        var packets: [EncodedAudioPacket] = []
        var consumed = 0
        while pending.count - consumed >= samplesPerFrame {
            packets.append(try encodeFrame(at: consumed))
            consumed += samplesPerFrame
        }
        pending.removeFirst(consumed)
        pendingStartFrame += Int64(consumed / Int(channelCount))
        return packets
    }

    /// Pads the final partial frame with silence and encodes it.
    func flush() throws -> [EncodedAudioPacket] {
        guard !pending.isEmpty else { return [] }
        let samplesPerFrame = Self.frameSize * Int(channelCount)
        pending.append(contentsOf: repeatElement(0, count: samplesPerFrame - pending.count))
        let packet = try encodeFrame(at: 0)
        pending.removeAll()
        return [packet]
    }

    private func appendToPending(_ stereo: [Float]) {
        guard channelCount == 1 else {
            pending.append(contentsOf: stereo)
            return
        }
        pending.reserveCapacity(pending.count + stereo.count / 2)
        var index = 0
        while index + 1 < stereo.count {
            pending.append((stereo[index] + stereo[index + 1]) * 0.5)
            index += 2
        }
    }

    private func encodeFrame(at sampleOffset: Int) throws -> EncodedAudioPacket {
        let byteCount = pending.withUnsafeBufferPointer { samples in
            opus_encode_float(encoder, samples.baseAddress! + sampleOffset, Int32(Self.frameSize),
                              &outputBuffer, Int32(outputBuffer.count))
        }
        guard byteCount > 0 else {
            throw EncodingError.encoderFailure("opus_encode_float failed (\(Self.describe(byteCount)))")
        }
        let startFrame = pendingStartFrame + Int64(sampleOffset / Int(channelCount))
        let rate = Int64(Self.sampleRate)
        let pts = startFrame * 1_000 / rate
        let end = (startFrame + Int64(Self.frameSize)) * 1_000 / rate
        return EncodedAudioPacket(data: Data(outputBuffer[0..<Int(byteCount)]),
                                  ptsMilliseconds: pts, durationMilliseconds: end - pts)
    }

    private static func describe(_ status: Int32) -> String {
        String(cString: opus_strerror(status))
    }
}

extension OpusAudioEncoder {
    /// Track description for `WebMMuxer`; `name` becomes the track's title in players.
    func webMTrack(named name: String? = nil) -> WebMMuxer.AudioTrack {
        WebMMuxer.AudioTrack(
            name: name,
            codecID: "A_OPUS",
            codecPrivate: identificationHeader,
            codecDelayNanoseconds: Self.codecDelayNanoseconds,
            seekPreRollNanoseconds: Self.seekPreRollNanoseconds,
            sampleRate: Double(Self.sampleRate),
            channelCount: Int(channelCount)
        )
    }
}
