import COpus
import Foundation

struct EncodedAudioPacket {
    let data: Data
    let ptsMilliseconds: Int64
    let durationMilliseconds: Int64
}

/// libopus wrapper: 48 kHz stereo, 20 ms frames.
final class OpusAudioEncoder {
    static let sampleRate: Int32 = 48_000
    static let channelCount: Int32 = 2
    static let frameSize = 960 // 20 ms at 48 kHz
    /// libopus' encoder lookahead for OPUS_APPLICATION_AUDIO at 48 kHz (Fs/400 + Fs/250).
    /// Hard-coded because `opus_encoder_ctl(OPUS_GET_LOOKAHEAD)` is variadic and Swift can't call it.
    static let preSkipFrames: UInt16 = 312
    static let seekPreRollNanoseconds: UInt64 = 80_000_000
    static var codecDelayNanoseconds: UInt64 { UInt64(preSkipFrames) * 1_000_000_000 / UInt64(sampleRate) }

    /// RFC 7845 §5.1 identification header, used as WebM CodecPrivate.
    static var identificationHeader: Data {
        var header = Data("OpusHead".utf8)
        header.append(1) // version
        header.append(UInt8(channelCount))
        withUnsafeBytes(of: preSkipFrames.littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: [0, 0]) // output gain
        header.append(0) // channel mapping family 0 (mono/stereo)
        return header
    }

    /// Transparent for speech and system sounds in a screen recording.
    private static let bitrate: Int32 = 96_000

    private let encoder: OpaquePointer
    /// Interleaved samples not yet encoded. The mixer output is gapless, so the
    /// timeline only needs the position of the first pending frame.
    private var pending: [Float] = []
    private var pendingStartFrame: Int64 = 0
    private var outputBuffer = [UInt8](repeating: 0, count: 4_000)

    init() throws {
        var status: Int32 = OPUS_OK
        guard let encoder = opus_encoder_create(Self.sampleRate, Self.channelCount, OPUS_APPLICATION_AUDIO, &status),
              status == OPUS_OK
        else { throw EncodingError.encoderSetup("opus_encoder_create failed (\(Self.describe(status)))") }
        let bitrateStatus = rec_opus_set_bitrate(encoder, Self.bitrate)
        guard bitrateStatus == OPUS_OK else {
            opus_encoder_destroy(encoder)
            throw EncodingError.encoderSetup("Opus bitrate setup failed (\(Self.describe(bitrateStatus)))")
        }
        self.encoder = encoder
    }

    deinit { opus_encoder_destroy(encoder) }

    /// Encodes every complete 20 ms frame; the remainder waits for more audio.
    func encode(_ chunk: StereoPCMChunk) throws -> [EncodedAudioPacket] {
        if pending.isEmpty { pendingStartFrame = chunk.startFrame }
        pending.append(contentsOf: chunk.samples)
        var packets: [EncodedAudioPacket] = []
        let samplesPerFrame = Self.frameSize * Int(Self.channelCount)
        var consumed = 0
        while pending.count - consumed >= samplesPerFrame {
            packets.append(try encodeFrame(at: consumed))
            consumed += samplesPerFrame
        }
        pending.removeFirst(consumed)
        pendingStartFrame += Int64(consumed / Int(Self.channelCount))
        return packets
    }

    /// Pads the final partial frame with silence and encodes it.
    func flush() throws -> [EncodedAudioPacket] {
        guard !pending.isEmpty else { return [] }
        let samplesPerFrame = Self.frameSize * Int(Self.channelCount)
        pending.append(contentsOf: repeatElement(0, count: samplesPerFrame - pending.count))
        let packet = try encodeFrame(at: 0)
        pending.removeAll()
        return [packet]
    }

    private func encodeFrame(at sampleOffset: Int) throws -> EncodedAudioPacket {
        let byteCount = pending.withUnsafeBufferPointer { samples in
            opus_encode_float(encoder, samples.baseAddress! + sampleOffset, Int32(Self.frameSize),
                              &outputBuffer, Int32(outputBuffer.count))
        }
        guard byteCount > 0 else {
            throw EncodingError.encoderFailure("opus_encode_float failed (\(Self.describe(byteCount)))")
        }
        let startFrame = pendingStartFrame + Int64(sampleOffset / Int(Self.channelCount))
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
