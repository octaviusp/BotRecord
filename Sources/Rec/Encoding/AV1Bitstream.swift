import Foundation

/// Minimal AV1 OBU handling needed for muxing: splitting OBUs, dropping temporal
/// delimiters (WebM/MP4 forbid them) and building the `av1C` configuration record.
enum AV1Bitstream {
    private enum OBUType: UInt8 {
        case sequenceHeader = 1
        case temporalDelimiter = 2
    }

    private struct OBU {
        let type: UInt8
        /// Full OBU bytes, header included.
        let range: Range<Int>
        let payload: Range<Int>
    }

    /// Returns `packet` without temporal delimiter OBUs.
    static func strippingTemporalDelimiters(_ packet: Data) throws -> Data {
        let obus = try parseOBUs(packet)
        guard obus.contains(where: { $0.type == OBUType.temporalDelimiter.rawValue }) else { return packet }
        var stripped = Data(capacity: packet.count)
        for obu in obus where obu.type != OBUType.temporalDelimiter.rawValue {
            stripped.append(packet[obu.range])
        }
        return stripped
    }

    /// Builds the AV1CodecConfigurationRecord (`av1C`, AV1-ISOBMFF §2.3) from the
    /// encoder's stream header. Used as WebM CodecPrivate and the MP4 `av1C` atom.
    static func codecConfigurationRecord(fromStreamHeader header: Data) throws -> Data {
        let obus = try parseOBUs(header)
        guard let sequenceOBU = obus.first(where: { $0.type == OBUType.sequenceHeader.rawValue }) else {
            throw EncodingError.encoderSetup("stream header has no AV1 sequence header OBU")
        }
        let info = try SequenceHeaderInfo(payload: Data(header[sequenceOBU.payload]))
        var record = Data([
            0x81, // marker = 1, version = 1
            info.profile << 5 | info.levelIndex & 0x1F,
            info.tier << 7 | info.highBitDepth << 6 | info.twelveBit << 5 | info.monochrome << 4
                | info.subsamplingX << 3 | info.subsamplingY << 2 | info.chromaSamplePosition & 0x3,
            0x00, // no initial_presentation_delay
        ])
        record.append(header[sequenceOBU.range])
        return record
    }

    private static func parseOBUs(_ data: Data) throws -> [OBU] {
        var obus: [OBU] = []
        var offset = data.startIndex
        while offset < data.endIndex {
            let start = offset
            let header = data[offset]
            let type = (header >> 3) & 0x0F
            let hasExtension = header & 0x04 != 0
            let hasSizeField = header & 0x02 != 0
            offset += hasExtension ? 2 : 1
            let payloadSize: Int
            if hasSizeField {
                let (value, length) = try readLEB128(data, at: offset)
                payloadSize = value
                offset += length
            } else {
                payloadSize = data.endIndex - offset
            }
            let payloadEnd = offset + payloadSize
            guard payloadEnd <= data.endIndex else {
                throw EncodingError.encoderFailure("truncated AV1 OBU in encoder output")
            }
            obus.append(OBU(type: type, range: start..<payloadEnd, payload: offset..<payloadEnd))
            offset = payloadEnd
        }
        return obus
    }

    private static func readLEB128(_ data: Data, at start: Int) throws -> (value: Int, length: Int) {
        var value = 0
        for index in 0..<8 {
            guard start + index < data.endIndex else { break }
            let byte = data[start + index]
            value |= Int(byte & 0x7F) << (index * 7)
            if byte & 0x80 == 0 { return (value, index + 1) }
        }
        throw EncodingError.encoderFailure("malformed OBU size field in encoder output")
    }
}

/// Fields of `sequence_header_obu()` (AV1 spec §5.5) that `av1C` repeats.
private struct SequenceHeaderInfo {
    var profile: UInt8 = 0
    var levelIndex: UInt8 = 0
    var tier: UInt8 = 0
    var highBitDepth: UInt8 = 0
    var twelveBit: UInt8 = 0
    var monochrome: UInt8 = 0
    var subsamplingX: UInt8 = 1
    var subsamplingY: UInt8 = 1
    var chromaSamplePosition: UInt8 = 0

    init(payload: Data) throws {
        var bits = BitReader(payload)
        profile = UInt8(try bits.read(3))
        _ = try bits.read(1) // still_picture
        let reducedStillPictureHeader = try bits.flag()
        var enableOrderHint = false
        if reducedStillPictureHeader {
            levelIndex = UInt8(try bits.read(5))
        } else {
            try parseOperatingPoints(&bits)
        }
        let widthBits = try bits.read(4) + 1
        let heightBits = try bits.read(4) + 1
        _ = try bits.read(widthBits)
        _ = try bits.read(heightBits)
        if !reducedStillPictureHeader, try bits.flag() { // frame_id_numbers_present_flag
            _ = try bits.read(4 + 3)
        }
        _ = try bits.read(3) // 128x128 superblock, filter intra, intra edge filter
        if !reducedStillPictureHeader {
            _ = try bits.read(4) // interintra, masked compound, warped motion, dual filter
            enableOrderHint = try bits.flag()
            if enableOrderHint { _ = try bits.read(2) } // jnt_comp, ref_frame_mvs
            let chooseScreenContentTools = try bits.flag()
            let forceScreenContentTools = chooseScreenContentTools ? 2 : try bits.read(1)
            if forceScreenContentTools > 0, !(try bits.flag()) { // seq_choose_integer_mv
                _ = try bits.read(1) // seq_force_integer_mv
            }
            if enableOrderHint { _ = try bits.read(3) }
        }
        _ = try bits.read(3) // superres, cdef, restoration
        try parseColorConfig(&bits)
    }

    private mutating func parseOperatingPoints(_ bits: inout BitReader) throws {
        var bufferDelayLength = 0
        var decoderModelInfoPresent = false
        if try bits.flag() { // timing_info_present_flag
            _ = try bits.read(32)
            _ = try bits.read(32)
            if try bits.flag() { try bits.skipUVLC() } // equal_picture_interval
            decoderModelInfoPresent = try bits.flag()
            if decoderModelInfoPresent {
                bufferDelayLength = try bits.read(5) + 1
                _ = try bits.read(32)
                _ = try bits.read(10) // removal + presentation time lengths
            }
        }
        let initialDisplayDelayPresent = try bits.flag()
        let operatingPointCount = try bits.read(5) + 1
        for index in 0..<operatingPointCount {
            _ = try bits.read(12) // operating_point_idc
            let level = UInt8(try bits.read(5))
            let tier = level > 7 ? UInt8(try bits.read(1)) : 0
            if index == 0 {
                levelIndex = level
                self.tier = tier
            }
            if decoderModelInfoPresent, try bits.flag() {
                _ = try bits.read(bufferDelayLength * 2 + 1)
            }
            if initialDisplayDelayPresent, try bits.flag() {
                _ = try bits.read(4)
            }
        }
    }

    private mutating func parseColorConfig(_ bits: inout BitReader) throws {
        highBitDepth = UInt8(try bits.read(1))
        if profile == 2, highBitDepth == 1 { twelveBit = UInt8(try bits.read(1)) }
        monochrome = profile == 1 ? 0 : UInt8(try bits.read(1))
        var primaries = 2, transfer = 2, matrix = 2
        if try bits.flag() { // color_description_present_flag
            primaries = try bits.read(8)
            transfer = try bits.read(8)
            matrix = try bits.read(8)
        }
        if monochrome == 1 { return }
        let isSRGBIdentity = primaries == 1 && transfer == 13 && matrix == 0
        if isSRGBIdentity {
            subsamplingX = 0
            subsamplingY = 0
            return
        }
        _ = try bits.read(1) // color_range
        switch profile {
        case 0: (subsamplingX, subsamplingY) = (1, 1)
        case 1: (subsamplingX, subsamplingY) = (0, 0)
        default:
            if twelveBit == 1 {
                subsamplingX = UInt8(try bits.read(1))
                subsamplingY = subsamplingX == 1 ? UInt8(try bits.read(1)) : 0
            } else {
                (subsamplingX, subsamplingY) = (1, 0)
            }
        }
        if subsamplingX == 1, subsamplingY == 1 {
            chromaSamplePosition = UInt8(try bits.read(2))
        }
    }
}

private struct BitReader {
    private let bytes: [UInt8]
    private var bitPosition = 0

    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func read(_ count: Int) throws -> Int {
        var value = 0
        for _ in 0..<count {
            let byteIndex = bitPosition >> 3
            guard byteIndex < bytes.count else {
                throw EncodingError.encoderSetup("AV1 sequence header is truncated")
            }
            let bit = (bytes[byteIndex] >> (7 - UInt8(bitPosition & 7))) & 1
            value = value << 1 | Int(bit)
            bitPosition += 1
        }
        return value
    }

    mutating func flag() throws -> Bool { try read(1) == 1 }

    mutating func skipUVLC() throws {
        var leadingZeros = 0
        while try read(1) == 0 {
            leadingZeros += 1
            guard leadingZeros < 32 else { throw EncodingError.encoderSetup("malformed uvlc in sequence header") }
        }
        _ = try read(leadingZeros)
    }
}
