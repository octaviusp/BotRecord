import AppKit
import SwiftUI

/// One past recording: thumbnail, title, meta, and (on hover) copy + reveal.
struct RecentRow: View {
    let recording: RecentRecording
    let transcript: TranscriptStatus

    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.recentTitle(for: recording.createdAt)).font(.system(size: 13, weight: .medium))
                Text(meta).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isHovering { actions }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(isHovering ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(recording.url) }
        .onPointerHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Open \(recording.url.lastPathComponent)")
    }

    private var meta: String {
        var parts: [String] = []
        if let metadata = recording.metadata { parts.append(Formatters.duration(metadata.duration)) }
        parts.append(Formatters.fileSize(recording.fileSize))
        if let metadata = recording.metadata { parts.append(metadata.format.containerLabel) }
        parts.append(transcript.label)
        return parts.joined(separator: " · ")
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = recording.thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.primary.opacity(0.1))
                    .overlay(Image(systemName: "film").foregroundStyle(.tertiary))
            }
            if let metadata = recording.metadata {
                Text(Formatters.duration(metadata.duration))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(3)
            }
        }
        .frame(width: 60, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 4) {
            iconButton(didCopy ? "checkmark" : "doc.on.doc", tint: didCopy ? Theme.success : nil, help: "Copy to clipboard", action: copy)
            iconButton("folder", tint: nil, help: "Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([recording.url])
            }
        }
    }

    private func iconButton(_ symbol: String, tint: Color?, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint ?? Color.secondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func copy() {
        do {
            try FileClipboard.copy(recording.url)
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } catch {
            NSSound.beep()
        }
    }
}
