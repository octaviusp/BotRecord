import AppKit

/// Sidecar facts about a recording that the file itself can't give cheaply (duration, pixel size).
struct RecordingMetadata: Codable, Equatable {
    let duration: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
    let format: OutputFormat

    init(result: RecordingResult) {
        duration = result.duration
        pixelWidth = Int(result.pixelSize.width)
        pixelHeight = Int(result.pixelSize.height)
        format = result.format
    }
}

struct RecentRecording: Identifiable {
    let url: URL
    let createdAt: Date
    let fileSize: Int64
    /// Nil for files recorded elsewhere or before metadata existed.
    let metadata: RecordingMetadata?
    let thumbnail: NSImage?
    /// `<name>.md` exists next to the video.
    let hasTranscript: Bool

    var id: URL { url }
}
