import Foundation

/// A meeting's `transcript.json` and `transcript.md` (see `TranscriptWriter`).
struct MeetingTranscriptFiles: TranscriptOutput {
    let folder: URL

    func write(_ segments: [TranscriptSegment]) throws {
        try TranscriptWriter.write(segments, to: folder)
    }
}

/// A screen recording's transcript next to the video: `<name>.md` to read, `<name>.vtt` captions for players.
struct RecordingTranscriptFiles: TranscriptOutput {
    let videoURL: URL

    var markdownURL: URL { videoURL.deletingPathExtension().appendingPathExtension("md") }
    var captionsURL: URL { videoURL.deletingPathExtension().appendingPathExtension("vtt") }

    func write(_ segments: [TranscriptSegment]) throws {
        try Data(markdown(segments).utf8).write(to: markdownURL, options: .atomic)
        try Data(WebVTT.document(segments).utf8).write(to: captionsURL, options: .atomic)
    }

    /// `[mm:ss] text` per utterance, no speakers: a recording usually has one narrator.
    private func markdown(_ segments: [TranscriptSegment]) -> String {
        let lines = segments.map { "[\(TranscriptWriter.timestamp($0.start))] \($0.text)" }
        return "# \(videoURL.lastPathComponent)\n\n" + lines.joined(separator: "\n") + "\n"
    }
}

/// WebVTT captions, one cue per segment.
enum WebVTT {
    static func document(_ segments: [TranscriptSegment]) -> String {
        let cues = segments.enumerated().map { index, segment in
            "\(index + 1)\n\(timestamp(segment.start)) --> \(timestamp(max(segment.end, segment.start + 0.5)))\n\(cueText(segment.text))"
        }
        return (["WEBVTT"] + cues).joined(separator: "\n\n") + "\n"
    }

    /// `hh:mm:ss.mmm`, the form every player accepts.
    static func timestamp(_ seconds: TimeInterval) -> String {
        let milliseconds = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d.%03d",
                      milliseconds / 3_600_000, milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000)
    }

    /// "-->" and blank lines would break the cue; "&" and "<" would start entities and tags.
    private static func cueText(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "-->", with: "→")
            .components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
