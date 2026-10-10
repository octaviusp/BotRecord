import Foundation

/// Writes a meeting's transcript twice: `transcript.json` for programs, `transcript.md` for people and agents.
enum TranscriptWriter {
    static func write(_ segments: [TranscriptSegment], to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(segments).write(to: folder.appendingPathComponent(MeetingFiles.transcriptJSON), options: .atomic)
        try Data(markdown(segments).utf8).write(to: folder.appendingPathComponent(MeetingFiles.transcriptMarkdown), options: .atomic)
    }

    /// One line per utterance: `[mm:ss] Me: …` / `[mm:ss] Otros: …`, in time order.
    static func markdown(_ segments: [TranscriptSegment]) -> String {
        segments
            .sorted { $0.start < $1.start }
            .map { "[\(timestamp($0.start))] \(speaker($0.track)): \($0.text.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n") + "\n"
    }

    /// Minutes keep counting past an hour ("[62:10]") so every timestamp has the same `mm:ss` shape.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func speaker(_ track: MeetingTrack) -> String {
        switch track {
        case .me: "Me"
        case .others: "Otros"
        }
    }
}
