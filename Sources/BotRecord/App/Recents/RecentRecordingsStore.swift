import AppKit
import Observation
import os

/// Latest screen recordings (output folder, with sidecar metadata and thumbnails kept in the app's cache so
/// that folder stays clean) and latest meetings (library), mixed by date.
@MainActor @Observable
final class RecentRecordingsStore {
    static let visibleCount = 3

    private(set) var items: [RecentItem] = []
    /// Newest meeting even when screen recordings push it out of `items`: the summary button follows it.
    private(set) var latestMeeting: MeetingEntry?

    private let settings: AppSettings
    private let logger = Logger(subsystem: AppPaths.identifier, category: "recents")
    private static let videoExtensions: Set<String> = ["webm", "mp4"]

    init(settings: AppSettings) {
        self.settings = settings
    }

    func reload() {
        let meetings = settings.library.latestMeetings(limit: Self.visibleCount)
        latestMeeting = meetings.first
        let mixed = latestFiles().map { RecentItem.screen(makeRecording($0)) } + meetings.map(RecentItem.meeting)
        items = Array(mixed.sorted { $0.createdAt > $1.createdAt }.prefix(Self.visibleCount))
    }

    /// Persists metadata and thumbnail for a fresh recording, then refreshes the list.
    func remember(_ result: RecordingResult) async {
        let metadataURL = sidecarURL(for: result.url, extension: "json")
        let thumbnailURL = sidecarURL(for: result.url, extension: "png")
        let metadata = RecordingMetadata(result: result)
        let thumbnail = result.thumbnail
        let logger = logger
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: AppPaths.recentsDirectory, withIntermediateDirectories: true)
                try JSONEncoder().encode(metadata).write(to: metadataURL, options: .atomic)
                if let thumbnail, let png = ThumbnailEncoder.pngData(from: thumbnail) {
                    try png.write(to: thumbnailURL, options: .atomic)
                }
            } catch {
                logger.error("Could not store recent metadata: \(error.localizedDescription)")
            }
        }.value
        reload()
    }

    private func latestFiles() -> [(url: URL, createdAt: Date, size: Int64)] {
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey, .fileSizeKey]
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: settings.outputDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
        return contents
            .filter { Self.videoExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { url -> (URL, Date, Int64)? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
                let date = values.creationDate ?? values.contentModificationDate ?? .distantPast
                return (url, date, Int64(values.fileSize ?? 0))
            }
            .sorted { $0.1 > $1.1 }
            .prefix(Self.visibleCount)
            .map { (url: $0.0, createdAt: $0.1, size: $0.2) }
    }

    private func makeRecording(_ file: (url: URL, createdAt: Date, size: Int64)) -> RecentRecording {
        let metadata = (try? Data(contentsOf: sidecarURL(for: file.url, extension: "json")))
            .flatMap { try? JSONDecoder().decode(RecordingMetadata.self, from: $0) }
        let thumbnail = NSImage(contentsOf: sidecarURL(for: file.url, extension: "png"))
        let hasTranscript = FileManager.default.fileExists(atPath: RecordingTranscriptFiles(videoURL: file.url).markdownURL.path)
        return RecentRecording(url: file.url, createdAt: file.createdAt, fileSize: file.size, metadata: metadata,
                               thumbnail: thumbnail, hasTranscript: hasTranscript)
    }

    private func sidecarURL(for recording: URL, extension ext: String) -> URL {
        AppPaths.recentsDirectory.appendingPathComponent(recording.lastPathComponent + "." + ext)
    }
}
