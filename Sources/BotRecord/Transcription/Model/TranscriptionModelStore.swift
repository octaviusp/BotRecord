import Foundation
import Observation
import os

/// The on-device speech model's lifecycle as Settings shows it: not downloaded → downloading → ready.
@MainActor @Observable
final class TranscriptionModelStore {
    enum State: Equatable {
        /// `resumeFraction` is how much an interrupted download already holds.
        case notDownloaded(resumeFraction: Double?)
        case downloading(fraction: Double)
        case ready
        case failed(message: String)
    }

    private(set) var state: State
    /// Language tags listed in the model's `languages.json`; empty until ready.
    private(set) var supportedLanguages: Set<String> = []

    let manifest: TranscriptionModelManifest
    @ObservationIgnored private let installer: ModelInstaller
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: AppPaths.identifier, category: "model")

    init(manifest: TranscriptionModelManifest = .nemotron, root: URL = AppPaths.modelsDirectory) {
        self.manifest = manifest
        installer = ModelInstaller(manifest: manifest, root: root)
        state = .notDownloaded(resumeFraction: nil)
        if installer.isInstalled {
            loadLanguages()
        } else {
            state = .notDownloaded(resumeFraction: resumeFraction())
        }
    }

    var isReady: Bool { state == .ready }

    /// The folder to load the model from, once it is ready.
    var installedFolder: URL? { isReady ? installer.installedFolder : nil }

    func supports(_ language: TranscriptionLanguage) -> Bool {
        supportedLanguages.contains(language.rawValue)
    }

    func download() {
        switch state {
        case .downloading, .ready: return
        case .notDownloaded, .failed: break
        }
        state = .downloading(fraction: resumeFraction() ?? 0)
        let total = manifest.totalBytes
        let lastPercent = OSAllocatedUnfairLock(initialState: -1)
        let installer = installer
        downloadTask = Task {
            do {
                try await installer.install { bytes in
                    // ~100 UI updates for the whole download instead of one per network packet.
                    let percent = Int(bytes * 100 / max(total, 1))
                    guard lastPercent.withLock({ last in defer { last = percent }; return last != percent }) else { return }
                    Task { @MainActor [weak self] in self?.showProgress(Double(bytes) / Double(total)) }
                }
                loadLanguages()
            } catch {
                finishFailedDownload(error)
            }
            downloadTask = nil
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// Deletes the model files (and any partial download). The caller unloads the engine first.
    func delete() throws {
        downloadTask?.cancel()
        try installer.remove()
        supportedLanguages = []
        state = .notDownloaded(resumeFraction: nil)
    }

    // MARK: Private

    private func showProgress(_ fraction: Double) {
        guard case .downloading = state else { return }
        state = .downloading(fraction: min(fraction, 1))
    }

    private func finishFailedDownload(_ error: Error) {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
            state = .notDownloaded(resumeFraction: resumeFraction())
        } else {
            logger.error("Model download failed: \(error.localizedDescription)")
            state = .failed(message: error.localizedDescription)
        }
    }

    private func resumeFraction() -> Double? {
        let staged = installer.stagedBytes
        return staged > 0 ? Double(staged) / Double(manifest.totalBytes) : nil
    }

    private struct LanguageMap: Decodable {
        let promptDictionary: [String: Int]
    }

    private func loadLanguages() {
        let url = installer.installedFolder.appendingPathComponent("languages.json")
        do {
            let map = try JSONDecoder().decode(LanguageMap.self, from: Data(contentsOf: url))
            supportedLanguages = Set(map.promptDictionary.keys)
            state = .ready
        } catch {
            logger.error("Unreadable languages.json: \(error.localizedDescription)")
            state = .failed(message: "The downloaded model is unreadable (languages.json). Delete it and download again.")
        }
    }
}

/// Transcript languages offered in Settings. Tags must exist in the model's `languages.json`.
enum TranscriptionLanguage: String, CaseIterable, Codable, Sendable {
    /// "es-US" (prompt slot 3, what the reference Python "es" uses); "es-ES" returned empty text on Rioplatense clips.
    case spanish = "es-US"
    case english = "en-US"

    /// First-launch default: Spanish for Spanish-speaking systems, English otherwise.
    static var matchingSystemLanguage: TranscriptionLanguage {
        Locale.current.language.languageCode == .spanish ? .spanish : .english
    }

    var label: String {
        switch self {
        case .spanish: "Español"
        case .english: "English"
        }
    }
}
