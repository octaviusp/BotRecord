import Foundation

/// EBML (RFC 8794) element encoding. Element IDs are passed with their length marker bits,
/// exactly as the Matroska spec lists them (e.g. `0x1A45DFA3`).
enum EBML {
    /// Size field meaning "unknown"; patched later with `fixedSize`.
    static let unknownSize = Data([0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])

    static func id(_ id: UInt32) -> Data {
        let byteCount = id > 0xFF_FFFF ? 4 : id > 0xFFFF ? 3 : id > 0xFF ? 2 : 1
        return Data((0..<byteCount).reversed().map { UInt8(truncatingIfNeeded: id >> ($0 * 8)) })
    }

    /// Shortest variable-length size. All-ones values are reserved, hence `- 1`.
    static func size(_ value: Int) -> Data {
        var length = 1
        while UInt64(value) >= (UInt64(1) << (7 * length)) - 1 { length += 1 }
        return vint(UInt64(value), length: length)
    }

    /// 8-byte size, used where the value is patched in place after writing.
    static func fixedSize(_ value: Int) -> Data { vint(UInt64(value), length: 8) }

    static func element(_ id: UInt32, _ payload: Data) -> Data {
        var data = self.id(id)
        data.append(size(payload.count))
        data.append(payload)
        return data
    }

    static func master(_ id: UInt32, _ children: [Data]) -> Data {
        element(id, children.reduce(into: Data()) { $0.append($1) })
    }

    static func unsigned(_ id: UInt32, _ value: UInt64) -> Data {
        var bytes = withUnsafeBytes(of: value.bigEndian) { Data($0) }
        while bytes.count > 1, bytes.first == 0 { bytes.removeFirst() }
        return element(id, bytes)
    }

    static func float(_ id: UInt32, _ value: Double) -> Data {
        element(id, withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) })
    }

    static func string(_ id: UInt32, _ value: String) -> Data {
        element(id, Data(value.utf8))
    }

    /// A Void element occupying exactly `totalBytes` (minimum 2).
    static func void(totalBytes: Int) -> Data {
        precondition(totalBytes >= 2, "Void needs at least 2 bytes")
        var payloadSize = totalBytes - 2
        var sizeField = size(payloadSize)
        if 1 + sizeField.count + payloadSize != totalBytes {
            payloadSize = totalBytes - 1 - 8
            sizeField = fixedSize(payloadSize)
        }
        var data = id(MatroskaID.void)
        data.append(sizeField)
        data.append(Data(count: payloadSize))
        return data
    }

    private static func vint(_ value: UInt64, length: Int) -> Data {
        let marked = value | (UInt64(1) << (7 * length))
        return Data((0..<length).reversed().map { UInt8(truncatingIfNeeded: marked >> ($0 * 8)) })
    }
}

/// Matroska/WebM element IDs used by `WebMMuxer`.
enum MatroskaID {
    static let ebml: UInt32 = 0x1A45_DFA3
    static let ebmlVersion: UInt32 = 0x4286
    static let ebmlReadVersion: UInt32 = 0x42F7
    static let ebmlMaxIDLength: UInt32 = 0x42F2
    static let ebmlMaxSizeLength: UInt32 = 0x42F3
    static let docType: UInt32 = 0x4282
    static let docTypeVersion: UInt32 = 0x4287
    static let docTypeReadVersion: UInt32 = 0x4285

    static let segment: UInt32 = 0x1853_8067
    static let seekHead: UInt32 = 0x114D_9B74
    static let seek: UInt32 = 0x4DBB
    static let seekID: UInt32 = 0x53AB
    static let seekPosition: UInt32 = 0x53AC
    static let void: UInt32 = 0xEC

    static let info: UInt32 = 0x1549_A966
    static let timestampScale: UInt32 = 0x2A_D7B1
    static let muxingApp: UInt32 = 0x4D80
    static let writingApp: UInt32 = 0x5741
    static let duration: UInt32 = 0x4489

    static let tracks: UInt32 = 0x1654_AE6B
    static let trackEntry: UInt32 = 0xAE
    static let trackNumber: UInt32 = 0xD7
    static let trackUID: UInt32 = 0x73C5
    static let trackType: UInt32 = 0x83
    static let flagLacing: UInt32 = 0x9C
    static let name: UInt32 = 0x536E
    static let codecID: UInt32 = 0x86
    static let codecPrivate: UInt32 = 0x63A2
    static let codecDelay: UInt32 = 0x56AA
    static let seekPreRoll: UInt32 = 0x56BB
    static let video: UInt32 = 0xE0
    static let pixelWidth: UInt32 = 0xB0
    static let pixelHeight: UInt32 = 0xBA
    static let colour: UInt32 = 0x55B0
    static let matrixCoefficients: UInt32 = 0x55B1
    static let range: UInt32 = 0x55B9
    static let transferCharacteristics: UInt32 = 0x55BA
    static let primaries: UInt32 = 0x55BB
    static let audio: UInt32 = 0xE1
    static let samplingFrequency: UInt32 = 0xB5
    static let channels: UInt32 = 0x9F

    static let cluster: UInt32 = 0x1F43_B675
    static let timestamp: UInt32 = 0xE7
    static let simpleBlock: UInt32 = 0xA3

    static let cues: UInt32 = 0x1C53_BB6B
    static let cuePoint: UInt32 = 0xBB
    static let cueTime: UInt32 = 0xB3
    static let cueTrackPositions: UInt32 = 0xB7
    static let cueTrack: UInt32 = 0xF7
    static let cueClusterPosition: UInt32 = 0xF1
}
