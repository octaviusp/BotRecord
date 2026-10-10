import CoreGraphics
import Foundation

enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case fullScreen, area
}

enum VideoResolution: Int, CaseIterable, Codable, Sendable {
    case p720 = 720
    case p1080 = 1080

    var label: String { "\(rawValue)p" }
}

enum VideoFrameRate: Int, CaseIterable, Codable, Sendable {
    case fps30 = 30
    case fps60 = 60

    var label: String { "\(rawValue) fps" }
}

enum OutputFormat: String, CaseIterable, Codable, Sendable {
    case webmAV1, mp4AV1, mp4H264

    var fileExtension: String { self == .webmAV1 ? "webm" : "mp4" }

    var label: String {
        switch self {
        case .webmAV1: "WebM · AV1"
        case .mp4AV1: "MP4 · AV1"
        case .mp4H264: "MP4 · H.264"
        }
    }

    /// Short label for the popover's two-way switch.
    var containerLabel: String { self == .webmAV1 ? "WebM" : "MP4" }
}

/// Encoder effort for AV1 formats. Ignored by hardware H.264.
enum CompressionEffort: String, CaseIterable, Codable, Sendable {
    case fastest, balanced, smallest

    var label: String { rawValue.capitalized }
}

enum AudioSource: Sendable {
    case system, microphone
}

/// Everything the recorder needs, snapshotted from settings when Record is pressed.
struct RecordingOptions: Sendable {
    var resolution: VideoResolution
    var frameRate: VideoFrameRate
    var format: OutputFormat
    var compression: CompressionEffort
    var showCursor: Bool
    var highlightClicks: Bool
    var captureMicrophone: Bool
    var captureSystemAudio: Bool
    var outputDirectory: URL
}

/// What to capture. `sourceRect` is in display-local points with a top-left origin
/// (the same space as `SCStreamConfiguration.sourceRect`); nil means the whole display.
struct CaptureTarget: Sendable, Equatable {
    let displayID: CGDirectDisplayID
    let sourceRect: CGRect?
}

/// Encoder input description shared by every `MediaSink`.
struct VideoEncodeConfig: Sendable {
    /// Output pixel size, always even.
    let width: Int
    let height: Int
    let frameRate: Int
    let compression: CompressionEffort
    /// Audio sources that will be appended; empty means no audio track.
    let audioSources: Set<AudioSource>
}

struct RecordingResult: @unchecked Sendable {
    let url: URL
    /// Hardware H.264 copy recorded in parallel for "Copy as MP4"; nil when the main file is already H.264.
    let companionMP4URL: URL?
    let duration: TimeInterval
    let fileSize: Int64
    let pixelSize: CGSize
    let format: OutputFormat
    let thumbnail: CGImage?
}

/// Raised mid-recording (disk full, stream interrupted). The recorder finalizes what it has first.
struct RecordingFailure: Error, @unchecked Sendable {
    let message: String
    let underlying: Error?
    let partialResult: RecordingResult?
}
