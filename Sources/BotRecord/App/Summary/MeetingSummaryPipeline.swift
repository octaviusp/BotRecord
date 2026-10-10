import Foundation
import os

/// Everything "Generar resumen detallado" does to the library once the summarizer answers:
/// write summary.md, record it in meta.json, name the folder after the title and log the decisions.
struct MeetingSummaryPipeline: Sendable {
    struct Outcome: Sendable {
        /// The meeting folder after the rename.
        let folder: URL
        let summaryURL: URL
        let title: String?
        let account: String
        let decisionCount: Int
    }

    let library: MeetingLibrary
    let summarizer: MeetingSummarizing

    private static let logger = Logger(subsystem: AppPaths.identifier, category: "summary")

    func run(meetingFolder folder: URL) async throws -> Outcome {
        let transcriptURL = folder.appendingPathComponent(MeetingFiles.transcriptMarkdown)
        guard let transcript = try? String(contentsOf: transcriptURL, encoding: .utf8),
              !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummaryError.missingTranscript
        }
        var metadata = try? MeetingMetadata.read(from: folder)
        let summary = try await summarizer.summarize(SummaryRequest(
            transcript: transcript,
            startedAt: metadata?.startedAt,
            duration: metadata?.durationSeconds
        ))
        try Task.checkCancellation()

        let document = SummaryDocument(markdown: summary.markdown)
        try Data(summary.markdown.utf8).write(to: folder.appendingPathComponent(MeetingFiles.summary), options: .atomic)
        if var updated = metadata {
            updated.title = document.title
            updated.summary = .init(model: summary.model, account: summary.account, createdAt: Date())
            updated.files = MeetingFiles.present(in: folder)
            try updated.write(to: folder)
            metadata = updated
        }

        let finalFolder = renamed(folder, metadata: metadata, title: document.title)
        if let metadata, let title = document.title {
            try library.decisions.append(
                date: metadata.startedAt,
                title: title,
                decisions: document.decisions,
                meetingPath: library.relativePath(of: finalFolder)
            )
        }
        return Outcome(
            folder: finalFolder,
            summaryURL: finalFolder.appendingPathComponent(MeetingFiles.summary),
            title: document.title,
            account: summary.account,
            decisionCount: document.decisions.count
        )
    }

    /// The summary is already saved, so a failed rename only costs a less descriptive folder name.
    private func renamed(_ folder: URL, metadata: MeetingMetadata?, title: String?) -> URL {
        guard let metadata, let title else { return folder }
        do {
            return try library.rename(folder, startedAt: metadata.startedAt, title: title)
        } catch {
            Self.logger.error("Could not rename \(folder.lastPathComponent): \(error.localizedDescription)")
            return folder
        }
    }
}
