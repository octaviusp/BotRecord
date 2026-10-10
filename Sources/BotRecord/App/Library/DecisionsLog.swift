import Foundation

/// `decisions.md`: one append-only log of every decision, so "what did we decide about X?" is a single grep.
struct DecisionsLog: Sendable {
    let url: URL

    private static let header = """
    # Decisions

    Append-only log of decisions taken in meetings, newest last. Each entry links to its meeting folder.

    """

    /// Appends `## 2026-10-10 · Pricing review`, the folder link and one bullet per decision.
    func append(date: Date, title: String, decisions: [String], meetingPath: String) throws {
        guard !decisions.isEmpty else { return }
        let entry = "\n## \(Self.dayFormatter.string(from: date)) · \(title)\n"
            + "[\(meetingPath)](\(meetingPath)/)\n\n"
            + decisions.map { "- \($0)" }.joined(separator: "\n") + "\n"
        try appendText(entry)
    }

    private func appendText(_ text: String) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            try Data(Self.header.utf8).write(to: url, options: .atomic)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
