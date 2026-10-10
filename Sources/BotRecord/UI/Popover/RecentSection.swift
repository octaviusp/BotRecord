import AppKit
import SwiftUI

/// Recent screen recordings and meetings, newest first, with the summary card at the bottom.
struct RecentSection: View {
    let recents: RecentRecordingsStore
    let summaries: SummaryController
    let connection: ClaudeConnection
    let transcription: TranscriptionService
    /// Opened by "Open folder ↗".
    let folder: URL

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Recent").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(action: openFolder) {
                    Text("Open folder ↗").font(.system(size: 11)).foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            if recents.items.isEmpty {
                Text("Your recordings will show up here")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                ForEach(recents.items) { item in
                    switch item {
                    case let .screen(recording):
                        RecentRow(recording: recording, transcript: status(recording.url, done: recording.hasTranscript))
                    case let .meeting(meeting):
                        RecentMeetingRow(meeting: meeting, transcript: status(meeting.folder, done: meeting.hasTranscript))
                    }
                }
            }

            // A summary of a transcript still being finalized would miss its last words.
            if let meeting = recents.latestMeeting, !transcription.isTranscribing(meeting.folder),
               summaries.offersSummary(for: meeting) {
                SummaryCard(meeting: meeting, summaries: summaries, connection: connection)
                    .padding(.top, 6)
            }
        }
    }

    private func status(_ url: URL, done: Bool) -> TranscriptStatus {
        transcription.isTranscribing(url) ? .transcribing : done ? .done : .off
    }

    private func openFolder() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(folder)
    }
}

struct PopoverFooter: View {
    let outputDirectory: URL

    var body: some View {
        HStack {
            Image(systemName: "externaldrive").font(.system(size: 10))
            Text(outputDirectory.path.abbreviatedPath)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .keyboardShortcut("q")
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 6)
    }
}
