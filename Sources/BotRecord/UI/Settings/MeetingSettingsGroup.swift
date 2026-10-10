import SwiftUI

/// Where meetings go and the defaults the popover starts from.
struct MeetingSettingsGroup: View {
    @Bindable var settings: AppSettings
    let connection: ClaudeConnection

    var body: some View {
        SettingsGroup(title: "Meetings") {
            SettingsRow(title: "Library folder", subtitle: "Meetings, summaries and decisions.md, readable by any AI agent") {
                FolderField(url: settings.libraryDirectory) {
                    if let url = FolderPicker.choose(startingAt: settings.libraryDirectory) { settings.libraryDirectory = url }
                }
            }
            SettingsRow(title: "Echo cancellation", subtitle: EchoCancellationHint.text(for: settings.meetingEchoCancellation)) {
                PillSegmented(options: EchoCancellationMode.allCases.map { ($0, $0.label) },
                              selection: $settings.meetingEchoCancellation)
            }
            ClaudeSettingsRow(connection: connection)
        }
    }
}

/// A folder path in a capsule with a "Change…" button.
struct FolderField: View {
    let url: URL
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(url.path.abbreviatedPath, systemImage: "folder")
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            Button("Change…", action: onChange)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
    }
}
