import Foundation

/// `meta.json`: the facts about one meeting that its media files can't give cheaply.
struct MeetingMetadata: Codable, Equatable, Sendable {
    struct Summary: Codable, Equatable, Sendable {
        let model: String
        /// Which Claude account produced it, e.g. "personal".
        let account: String
        let createdAt: Date
    }

    static let currentSchema = 1

    var schema = currentSchema
    let id: UUID
    /// Set from the summary's title; nil until summarized.
    var title: String?
    let startedAt: Date
    var durationSeconds: TimeInterval
    let tracks: [MeetingTrack]
    let echoCancellation: Bool
    /// Files present in the folder, relative names.
    var files: [String]
    var summary: Summary?

    func write(to folder: URL) throws {
        try Self.encoder.encode(self).write(to: folder.appendingPathComponent(MeetingFiles.metadata), options: .atomic)
    }

    static func read(from folder: URL) throws -> MeetingMetadata {
        let data = try Data(contentsOf: folder.appendingPathComponent(MeetingFiles.metadata))
        return try decoder.decode(MeetingMetadata.self, from: data)
    }

    // Local-offset ISO 8601 ("2026-10-10T14:30:00-03:00") so a human or an agent reads the wall-clock time directly.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter().string(from: date))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = isoFormatter().date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not ISO 8601: \(text)"))
            }
            return date
        }
        return decoder
    }

    private static func isoFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }
}

extension MeetingMetadata {
    /// Metadata for a meeting that just finished recording.
    init(id: UUID, capture: MeetingCaptureResult, options: MeetingOptions) {
        self.init(
            id: id,
            title: nil,
            startedAt: capture.startedAt,
            durationSeconds: capture.duration,
            tracks: options.captureMicrophone ? [.me, .others] : [.others],
            echoCancellation: options.echoCancellation,
            files: MeetingFiles.present(in: capture.folder),
            summary: nil
        )
    }
}
