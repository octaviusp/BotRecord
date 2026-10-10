import AppKit
import Observation

@MainActor @Observable
final class SavedToastModel {
    private(set) var copyState: CopyState
    private(set) var mp4State: CopyState = .idle
    /// Fraction of the auto-dismiss time already used, 0...1.
    private(set) var elapsedFraction = 0.0
    /// Pauses the auto-dismiss clock while the pointer is over the toast.
    var isHovering = false

    let recording: SavedRecording
    let thumbnail: NSImage?
    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private static let lifetime: TimeInterval = 10
    private static let stepSeconds = 0.05

    init(recording: SavedRecording) {
        self.recording = recording
        copyState = recording.alreadyCopied ? .copied : .idle
        thumbnail = recording.result.thumbnail.map { NSImage(cgImage: $0, size: .zero) }
    }

    var hasCompanion: Bool { recording.result.companionMP4URL != nil }

    var durationText: String { Formatters.duration(recording.result.duration) }

    var metaText: String {
        let result = recording.result
        return [
            durationText,
            Formatters.fileSize(result.fileSize),
            recording.qualityLabel,
            result.format.spokenLabel,
        ].joined(separator: " · ")
    }

    func startAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            let increment = Self.stepSeconds / Self.lifetime
            while elapsedFraction < 1 {
                do { try await Task.sleep(for: .seconds(Self.stepSeconds)) } catch { return }
                if !isHovering { elapsedFraction += increment }
            }
            onDismiss()
        }
    }

    func stopAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    func copyFile() {
        do {
            try FileClipboard.copy(recording.result.url)
            copyState = .copied
            if mp4State == .copied { mp4State = .idle }
        } catch {
            copyState = .failed(error.localizedDescription)
        }
    }

    func copyAsMP4() {
        guard let companion = recording.result.companionMP4URL, mp4State != .working else { return }
        let recordingURL = recording.result.url
        mp4State = .working
        Task {
            do {
                let exported = try await Task.detached(priority: .userInitiated) {
                    try FileClipboard.exportCompanion(companion, nextTo: recordingURL)
                }.value
                try FileClipboard.copy(exported)
                mp4State = .copied
                if copyState == .copied { copyState = .idle }
            } catch {
                mp4State = .failed(error.localizedDescription)
            }
        }
    }

    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([recording.result.url])
    }

    func openRecording() {
        NSWorkspace.shared.open(recording.result.url)
    }
}
