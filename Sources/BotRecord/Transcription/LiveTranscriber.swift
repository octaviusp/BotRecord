import Foundation
import os

/// The live transcript of one recording (a meeting, or a screen recording with audio).
///
/// Capture queues hand over audio through `liveAudio`, which only enqueues: each track has its own
/// bounded queue and worker, so recognition never blocks capture. If recognition falls behind, audio
/// waits in memory (up to `maxQueuedSeconds` per track) and is caught up; at RTF ≈ 0.05 it never does.
final class LiveTranscriber: LiveAudioObserver {
    struct Outcome: Sendable {
        let segments: [TranscriptSegment]
        /// The first recognition or write error; the segments before it are kept.
        let error: Error?
        /// Audio discarded because the queue was full; zero unless recognition stalled for minutes.
        let droppedSeconds: TimeInterval
    }

    struct Chunk: Sendable {
        let samples: [Float]
        let startTime: TimeInterval
    }

    /// 10 minutes of audio per track (~38 MB of Float32 at 16 kHz).
    private static let maxQueuedSeconds = 600
    private static let chunkSeconds = 0.2

    private let inputs: [MeetingTrack: AsyncStream<Chunk>.Continuation]
    private let workers: [Task<Void, Never>]
    private let collector: TranscriptCollector
    private let droppedSamples = OSAllocatedUnfairLock(initialState: 0)

    /// - Parameter output: written after every new segment; nil until the destination is known (`attach`).
    init(engine: SpeechTranscribing, language: String, output: TranscriptOutput?) {
        let collector = TranscriptCollector(output: output)
        let capacity = Int(Double(Self.maxQueuedSeconds) / Self.chunkSeconds)
        var inputs: [MeetingTrack: AsyncStream<Chunk>.Continuation] = [:]
        var workers: [Task<Void, Never>] = []
        for track in [MeetingTrack.me, .others] {
            let (stream, continuation) = AsyncStream.makeStream(of: Chunk.self, bufferingPolicy: .bufferingNewest(capacity))
            inputs[track] = continuation
            let worker = TrackTranscriber(track: track, engine: engine, language: language, collector: collector)
            workers.append(Task.detached(priority: .userInitiated) { await worker.run(stream) })
        }
        self.inputs = inputs
        self.workers = workers
        self.collector = collector
    }

    // MARK: LiveAudioObserver

    func liveAudio(_ samples: [Float], track: MeetingTrack, startTime: TimeInterval) {
        guard let input = inputs[track] else { return }
        if case let .dropped(oldest) = input.yield(Chunk(samples: samples, startTime: startTime)) {
            droppedSamples.withLock { $0 += oldest.samples.count }
        }
    }

    // MARK: Lifecycle

    /// Sets where the transcript goes when it wasn't known at start (a screen recording's file name).
    func attach(_ output: TranscriptOutput) async {
        await collector.attach(output)
    }

    /// Call after the recorder delivered its last audio: recognizes what is queued, closes open
    /// utterances and writes the final transcript.
    func finish() async -> Outcome {
        inputs.values.forEach { $0.finish() }
        for worker in workers { await worker.value }
        let dropped = droppedSamples.withLock { $0 }
        return await collector.complete(droppedSeconds: Double(dropped) / Double(SpeechSegmenter.sampleRate))
    }

    /// Stops recognizing and discards open utterances; whatever was already written stays.
    func cancel() {
        inputs.values.forEach { $0.finish() }
        workers.forEach { $0.cancel() }
    }
}

/// Segments one track and turns each utterance into a `TranscriptSegment`.
private struct TrackTranscriber: Sendable {
    let track: MeetingTrack
    let engine: SpeechTranscribing
    let language: String
    let collector: TranscriptCollector

    private struct OpenUtterance {
        let id: UtteranceID
        let onset: TimeInterval
    }

    func run(_ chunks: AsyncStream<LiveTranscriber.Chunk>) async {
        var segmenter = SpeechSegmenter()
        var open: OpenUtterance?
        var failed = false
        for await chunk in chunks where !failed {
            failed = await handle(segmenter.process(chunk.samples, startTime: chunk.startTime), open: &open)
        }
        if Task.isCancelled {
            if let open { await engine.discardUtterance(open.id) }
            return
        }
        if !failed { _ = await handle(segmenter.finish(), open: &open) }
    }

    /// Frame times carry binary noise (2.92000000001); files show milliseconds.
    private static func milliseconds(_ seconds: TimeInterval) -> TimeInterval {
        (seconds * 1000).rounded() / 1000
    }

    /// Returns true when recognition failed; the error is recorded and this track stops transcribing.
    private func handle(_ events: [SpeechSegmenter.Event], open: inout OpenUtterance?) async -> Bool {
        do {
            for event in events {
                switch event {
                case let .began(onset, leadIn):
                    open = OpenUtterance(id: try await engine.beginUtterance(language: language, leadIn: leadIn), onset: onset)
                case let .audio(samples):
                    if let open { try await engine.append(samples, to: open.id) }
                case let .ended(end):
                    guard let current = open else { continue }
                    open = nil
                    let text = try await engine.finishUtterance(current.id)
                    if !text.isEmpty {
                        await collector.add(TranscriptSegment(start: Self.milliseconds(current.onset), end: Self.milliseconds(end),
                                                              track: track, text: text))
                    }
                }
            }
            return false
        } catch {
            if let current = open { await engine.discardUtterance(current.id) }
            open = nil
            await collector.fail(error)
            return true
        }
    }
}
