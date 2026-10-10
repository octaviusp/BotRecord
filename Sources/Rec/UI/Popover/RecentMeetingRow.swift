import AppKit
import SwiftUI

/// One past meeting: icon, title, "42:10 · Teams · transcript ✓". Click opens the summary, or the folder before there is one.
struct RecentMeetingRow: View {
    let meeting: MeetingEntry
    let transcript: TranscriptStatus

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(meta).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovering { revealButton }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onPointerHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(meeting.hasSummary ? "Open summary" : "Open meeting folder")
    }

    private var title: String {
        meeting.metadata?.title ?? "Meeting · \(Formatters.recentTitle(for: meeting.startedAt))"
    }

    private var meta: String {
        var parts: [String] = []
        if let metadata = meeting.metadata {
            parts.append(Formatters.duration(metadata.durationSeconds))
        }
        parts.append(transcript.label)
        return parts.joined(separator: " · ")
    }

    /// Same 60×38 footprint as a recording thumbnail so mixed rows line up.
    private var icon: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.accent.opacity(0.14))
            .overlay(
                Image(systemName: meeting.hasSummary ? "doc.text" : "person.2.wave.2")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.accent)
            )
            .frame(width: 60, height: 38)
    }

    private var revealButton: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([meeting.folder])
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        .accessibilityLabel("Show in Finder")
    }

    private func open() {
        NSWorkspace.shared.open(meeting.hasSummary ? meeting.summaryURL : meeting.folder)
    }
}
