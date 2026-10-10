import SwiftUI

/// "Transcript" in the popover: a switch once the model is ready, otherwise what is missing and the way to get it.
struct TranscriptOptionRow: View {
    @Binding var isOn: Bool
    let transcription: TranscriptionService
    let onOpenSettings: () -> Void

    private static let icon = "text.quote"
    private static let title = "Transcript"

    var body: some View {
        if transcription.isAvailable {
            ToggleRow(icon: Self.icon, title: Self.title, isOn: $isOn)
        } else {
            OptionRow(icon: Self.icon, title: Self.title) { missingModel }
        }
    }

    @ViewBuilder
    private var missingModel: some View {
        switch transcription.models.state {
        case let .downloading(fraction):
            Text("Downloading \(Formatters.percent(fraction))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        case .ready:
            settingsLink("Choose language…")
        case .notDownloaded, .failed:
            settingsLink("Download model…")
        }
    }

    private func settingsLink(_ title: String) -> some View {
        Button(title, action: onOpenSettings)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.accent)
            .help("Smart transcript runs on this Mac once its model is downloaded in Settings")
    }
}
