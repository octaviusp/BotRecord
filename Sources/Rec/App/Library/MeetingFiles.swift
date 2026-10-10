import Foundation

/// File names inside a meeting folder. AGENTS.md documents them, so they are a public contract.
enum MeetingFiles {
    static let metadata = "meta.json"
    static let audio = "audio.webm"
    static let video = "video.webm"
    static let transcriptJSON = "transcript.json"
    static let transcriptMarkdown = "transcript.md"
    static let summary = "summary.md"

    /// Every file a meeting folder may hold, in the order meta.json lists them.
    static let all = [audio, video, transcriptJSON, transcriptMarkdown, summary]

    /// The files of `all` that exist in `folder`.
    static func present(in folder: URL) -> [String] {
        all.filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
}
