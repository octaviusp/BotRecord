import Foundation
import MLX
import NemotronStreamingASR
import os

/// Nemotron 3.5 ASR Streaming 0.6B (INT8, MLX on the GPU) behind `SpeechTranscribing`.
///
/// Loads lazily when a recording with transcription starts (0.06–0.2 s) and is unloaded by its owner as soon as
/// the last transcript is finished, so the ~760 MB of weights never sit in memory while BotRecord is idle.
/// Runs on its own serial queue: inference is synchronous GPU work (~14 ms per 320 ms of audio) that
/// must stay off the main thread and the capture queues. One recognizer session per open utterance;
/// speech-swift serializes them on one lock, so two tracks share the loaded weights.
actor TranscriptionEngine: SpeechTranscribing {
    enum EngineError: LocalizedError {
        case unsupportedLanguage(String)
        case unknownUtterance

        var errorDescription: String? {
            switch self {
            case let .unsupportedLanguage(tag): "The transcription model doesn't support the language “\(tag)”."
            case .unknownUtterance: "Transcription lost track of an utterance."
            }
        }
    }

    // Workaround (speech-swift 0.0.28): a fresh session drops the first words unless 320 ms of audio
    // precede them, so every utterance starts with its real lead-in, padded with silence to 320 ms.
    private static let leadInSamples = SpeechSegmenter.leadInSamples
    // Workaround (speech-swift 0.0.28): `finalize()` cuts the last words unless 640 ms of silence follow.
    private static let flushSamples = 10_240

    private let modelDirectory: URL
    private let modelID: String
    private let queue = DispatchSerialQueue(label: "\(AppPaths.identifier).transcription", qos: .userInitiated)
    private let logger = Logger(subsystem: AppPaths.identifier, category: "transcription")

    private var model: NemotronStreamingASRMLXModel?
    private var loading: Task<NemotronStreamingASRMLXModel, Error>?
    private var isWarm = false
    private var sessions: [UtteranceID: NemotronMLXStreamingSession] = [:]
    private var nextID: UInt64 = 0
    /// Bumped by `unload()`, so a load that was still running when the recording ended is dropped, not kept.
    private var generation: UInt64 = 0

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    init(modelDirectory: URL, modelID: String) {
        self.modelDirectory = modelDirectory
        self.modelID = modelID
    }

    // MARK: SpeechTranscribing

    func prepare() async throws {
        let model = try await loadedModel()
        // The first run of a new binary compiles Metal shaders (~2 s); later runs take ~20 ms.
        if !isWarm {
            try model.warmUp()
            isWarm = true
        }
    }

    func beginUtterance(language: String, leadIn: [Float]) async throws -> UtteranceID {
        let model = try await loadedModel()
        // Unknown tags silently fall back to "auto", which returned nothing on some Spanish clips.
        guard model.languages.promptDictionary[language] != nil else {
            throw EngineError.unsupportedLanguage(language)
        }
        let session = try model.createSession(language: language)
        let primer = leadIn.suffix(Self.leadInSamples)
        _ = try session.pushAudio([Float](repeating: 0, count: Self.leadInSamples - primer.count) + primer)
        nextID += 1
        let id = UtteranceID(rawValue: nextID)
        sessions[id] = session
        return id
    }

    func append(_ samples: [Float], to utterance: UtteranceID) throws {
        guard let session = sessions[utterance] else { throw EngineError.unknownUtterance }
        // Partial hypotheses are not shown live; only the final text of each utterance is kept.
        _ = try session.pushAudio(samples)
    }

    func finishUtterance(_ utterance: UtteranceID) throws -> String {
        guard let session = sessions.removeValue(forKey: utterance) else { throw EngineError.unknownUtterance }
        _ = try session.pushAudio([Float](repeating: 0, count: Self.flushSamples))
        let text = try session.finalize().last?.text ?? ""
        // The decoder sometimes joins sentences with two spaces.
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func discardUtterance(_ utterance: UtteranceID) {
        sessions.removeValue(forKey: utterance)
    }

    // MARK: Lifetime

    /// Frees the model now: after the last transcript, or before its files are deleted. Open utterances are dropped.
    func unload() {
        generation += 1
        loading?.cancel()
        loading = nil
        sessions.removeAll()
        guard model != nil else { return }
        model = nil
        isWarm = false
        // Released arrays go to MLX's buffer cache first; clearing it is what returns the memory.
        Memory.clearCache()
        logger.info("Transcription model unloaded")
    }

    private func loadedModel() async throws -> NemotronStreamingASRMLXModel {
        if let model { return model }
        let task = loading ?? Task { [modelDirectory, modelID] in
            try await NemotronStreamingASRMLXModel.fromDirectory(modelDirectory, modelId: modelID)
        }
        loading = task
        let requestedIn = generation
        do {
            let loaded = try await task.value
            guard generation == requestedIn else { throw CancellationError() }
            loading = nil
            model = loaded
            logger.info("Transcription model loaded from \(self.modelDirectory.lastPathComponent)")
            return loaded
        } catch {
            loading = nil
            throw error
        }
    }

}
