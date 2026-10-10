import AppKit
import SwiftUI

struct RecentSection: View {
    let recents: RecentRecordingsStore
    let outputDirectory: URL

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
                ForEach(recents.items) { RecentRow(recording: $0) }
            }
        }
    }

    private func openFolder() {
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(outputDirectory)
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
