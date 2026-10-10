import SwiftUI

/// "Smart transcript": the on-device model's status with the one action that fits it, and the language.
struct TranscriptSettingsGroup: View {
    @Bindable var settings: AppSettings
    let transcription: TranscriptionService

    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    private var models: TranscriptionModelStore { transcription.models }
    private var downloadSize: String { Formatters.fileSize(models.manifest.totalBytes) }

    var body: some View {
        SettingsGroup(title: "Smart transcript") {
            SettingsRow(title: "On-device model", subtitle: modelSubtitle) { modelControl }
            SettingsRow(title: "Language", subtitle: "What people speak in your meetings and recordings") {
                PillSegmented(options: languages.map { ($0, $0.label) }, selection: $settings.transcriptLanguage)
            }
        }
        .confirmationDialog("Delete the transcription model?", isPresented: $isConfirmingDelete) {
            Button("Delete \(downloadSize)", role: .destructive, action: deleteModel)
        } message: {
            Text("Transcripts stop until you download it again. Existing transcripts are kept.")
        }
    }

    /// Only tags the model lists; before it is downloaded every option is offered.
    private var languages: [TranscriptionLanguage] {
        let supported = TranscriptionLanguage.allCases.filter(models.supports)
        return supported.isEmpty ? TranscriptionLanguage.allCases : supported
    }

    private var modelSubtitle: String {
        if let deleteError { return deleteError }
        switch models.state {
        case .notDownloaded: return "Nemotron 3.5 Streaming · transcribes live on this Mac, audio never leaves it"
        case .downloading: return "Downloading Nemotron 3.5 Streaming · keep using BotRecord meanwhile"
        case .ready: return "Nemotron 3.5 Streaming · \(downloadSize) · transcripts are ready when you press Stop"
        case let .failed(message): return message
        }
    }

    @ViewBuilder
    private var modelControl: some View {
        switch models.state {
        case let .notDownloaded(resumeFraction):
            if let resumeFraction {
                capsuleButton("Resume · \(Formatters.percent(resumeFraction))", action: models.download)
            } else {
                capsuleButton("Download \(downloadSize)", action: models.download)
            }
        case let .downloading(fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 80)
                Text(Formatters.percent(fraction)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                capsuleButton("Cancel", action: models.cancelDownload)
            }
        case .ready:
            HStack(spacing: 8) {
                StatusBadge(title: "Ready", color: Theme.success)
                capsuleButton("Delete") { isConfirmingDelete = true }
                    .disabled(transcription.isBusy)
                    .help(transcription.isBusy ? "In use by a recording" : "Frees \(downloadSize)")
            }
        case .failed:
            capsuleButton("Retry", action: models.download)
        }
    }

    private func capsuleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
    }

    private func deleteModel() {
        Task {
            do {
                try await transcription.deleteModel()
                deleteError = nil
            } catch {
                deleteError = "Couldn't delete the model: \(error.localizedDescription)"
            }
        }
    }
}
