import Foundation

/// One meeting folder as found on disk.
struct MeetingEntry: Identifiable, Equatable, Sendable {
    let folder: URL
    /// Nil while recording, or when meta.json is missing or unreadable.
    let metadata: MeetingMetadata?
    let hasTranscript: Bool
    let hasSummary: Bool

    var id: URL { folder }

    /// Survives the folder rename after summarizing.
    var stableID: String { metadata?.id.uuidString ?? folder.path }

    var startedAt: Date { metadata?.startedAt ?? .distantPast }

    var transcriptURL: URL { folder.appendingPathComponent(MeetingFiles.transcriptMarkdown) }
    var summaryURL: URL { folder.appendingPathComponent(MeetingFiles.summary) }

    init(folder: URL) {
        self.folder = folder
        metadata = try? MeetingMetadata.read(from: folder)
        let manager = FileManager.default
        hasTranscript = manager.fileExists(atPath: folder.appendingPathComponent(MeetingFiles.transcriptMarkdown).path)
        hasSummary = manager.fileExists(atPath: folder.appendingPathComponent(MeetingFiles.summary).path)
    }
}

/// The on-disk library: `AGENTS.md`, `decisions.md` and `meetings/YYYY/MM/<meeting>/`.
/// Folder names start with the date, so lexical order is chronological and listing never reads metadata it won't show.
struct MeetingLibrary: Sendable {
    let root: URL

    var meetingsRoot: URL { root.appendingPathComponent("meetings", isDirectory: true) }
    var decisions: DecisionsLog { DecisionsLog(url: root.appendingPathComponent("decisions.md")) }

    /// Creates the root and writes `AGENTS.md` once; an existing guide is the user's to edit.
    func prepare() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: meetingsRoot, withIntermediateDirectories: true)
        let guide = root.appendingPathComponent(LibraryAgentsGuide.fileName)
        if !manager.fileExists(atPath: guide.path) {
            try Data(LibraryAgentsGuide.text.utf8).write(to: guide, options: .atomic)
        }
    }

    /// `meetings/YYYY/MM/<YYYY-MM-DD-HHmm>-meeting/`, made unique when two meetings start the same minute.
    func createMeetingFolder(startedAt: Date) throws -> URL {
        try prepare()
        let month = monthFolder(for: startedAt)
        try FileManager.default.createDirectory(at: month, withIntermediateDirectories: true)
        let folder = uniqueFolder(in: month, name: FolderNaming.initialName(startedAt: startedAt))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    /// Renames to `<date>-<title-slug>`; returns the folder unchanged when the name already matches.
    func rename(_ folder: URL, startedAt: Date, title: String) throws -> URL {
        let name = FolderNaming.titledName(startedAt: startedAt, title: title)
        guard name != folder.lastPathComponent else { return folder }
        let destination = uniqueFolder(in: folder.deletingLastPathComponent(), name: name)
        try FileManager.default.moveItem(at: folder, to: destination)
        return destination
    }

    func discard(_ folder: URL) throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// Path relative to the library root, e.g. `meetings/2026/10/2026-10-10-1430-pricing`.
    func relativePath(of folder: URL) -> String {
        let rootPath = root.standardizedFileURL.path + "/"
        let path = folder.standardizedFileURL.path
        return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
    }

    /// Newest finished meetings first, reading only as many year/month folders as needed.
    /// A folder without meta.json is still recording (or was abandoned) and is skipped.
    func latestMeetings(limit: Int) -> [MeetingEntry] {
        var found: [MeetingEntry] = []
        for year in subfolders(of: meetingsRoot) {
            for month in subfolders(of: year) {
                for folder in subfolders(of: month) {
                    let meeting = MeetingEntry(folder: folder)
                    guard meeting.metadata != nil else { continue }
                    found.append(meeting)
                    if found.count == limit { return found }
                }
            }
        }
        return found
    }

    private func monthFolder(for date: Date) -> URL {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return meetingsRoot
            .appendingPathComponent(String(format: "%04d", parts.year ?? 0), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", parts.month ?? 0), isDirectory: true)
    }

    private func uniqueFolder(in parent: URL, name: String) -> URL {
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name)-\(suffix)", isDirectory: true)
            suffix += 1
        }
        return candidate
    }

    /// Visible subfolders, newest name first.
    private func subfolders(of folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
