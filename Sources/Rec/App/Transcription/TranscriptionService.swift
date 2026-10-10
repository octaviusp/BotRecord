import Foundation
import Observation
import os

/// Smart transcript for the whole app: owns the model store and the engine, starts a `LiveTranscriber`
/// per recording, and tracks which outputs are still being finalized ("transcribing…" in Recent).
@MainActor @Observable
final class TranscriptionService {
    let models: TranscriptionModelStore
    /// Meeting folders and video files whose transcript is still being finalized.
    private(set) var inProgress: Set<URL> = []
    /// Live transcribers not yet finished or cancelled.
    private(set) var liveCount = 0

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var engine: TranscriptionEngine?
    @ObservationIgnored private let logger = Logger(subsystem: AppPaths.identifier, category: "transcription")

    init(settings: AppSettings, models: TranscriptionModelStore) {
        self.settings = settings
        self.models = models
    }

    /// True when a transcript can be made now: model downloaded and the chosen language supported.
    var isAvailable: Bool { models.isReady && models.supports(settings.transcriptLanguage) }

    func isTranscribing(_ url: URL) -> Bool { inProgress.contains(url) }

    /// The model can't be deleted while a recording is using it.
    var isBusy: Bool { liveCount > 0 || !inProgress.isEmpty }

    /// At launch: pays the one-time shader compilation now rather than at the first meeting.
    func warmUpIfEnabled() {
        guard settings.meetingTranscribe || settings.transcribeRecordings else { return }
        prepareEngine()
    }

    /// Loads and warms the model in the background; the engine unloads it again after 10 idle minutes.
    func prepareEngine() {
        guard isAvailable, let engine = currentEngine() else { return }
        let logger = logger
        Task {
            do {
                try await engine.prepare()
            } catch {
                logger.error("Transcription warm-up failed: \(error.localizedDescription)")
            }
        }
    }

    /// A transcriber to set as the recorder's audio observer, or nil when transcripts are unavailable.
    /// - Parameter output: where segments stream during the recording; nil to attach one in `finish`.
    func startLive(output: TranscriptOutput?) -> LiveTranscriber? {
        guard isAvailable, let engine = currentEngine() else { return nil }
        prepareEngine()
        liveCount += 1
        return LiveTranscriber(engine: engine, language: settings.transcriptLanguage.rawValue, output: output)
    }

    /// Finalizes the transcript once the recorder delivered its last audio. `key` shows as "transcribing…".
    func finish(_ transcriber: LiveTranscriber, output: TranscriptOutput?, trackedAs key: URL) async -> LiveTranscriber.Outcome {
        inProgress.insert(key)
        defer {
            inProgress.remove(key)
            liveCount -= 1
        }
        if let output { await transcriber.attach(output) }
        let outcome = await transcriber.finish()
        logger.info("Transcript of \(key.lastPathComponent): \(outcome.segments.count) segments")
        return outcome
    }

    func cancel(_ transcriber: LiveTranscriber) {
        transcriber.cancel()
        liveCount -= 1
    }

    /// Unloads the engine before deleting the files it may have mapped.
    func deleteModel() async throws {
        if let engine { await engine.unload() }
        engine = nil
        try models.delete()
    }

    private func currentEngine() -> TranscriptionEngine? {
        if let engine { return engine }
        guard let folder = models.installedFolder else { return nil }
        let created = TranscriptionEngine(modelDirectory: folder, modelID: models.manifest.modelID)
        engine = created
        return created
    }
}
