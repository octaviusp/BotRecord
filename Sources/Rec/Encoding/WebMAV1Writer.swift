import CoreMedia
import CoreVideo
import Foundation

/// Default sink: AV1 (SVT-AV1) + Opus in WebM.
///
/// Threads: `append*` on the capture queue, video packets on the encoder thread, all muxing
/// on a private serial queue, `finish`/`cancel` from the main actor.
final class WebMAV1Writer: MediaSink, @unchecked Sendable {
    /// Frames dropped because the encoder fell more than half a second behind.
    var droppedFrames: Int { encoder.droppedFrames }

    private let encoder: SvtAv1Encoder
    private let muxer: WebMMuxer
    private let muxQueue = DispatchQueue(label: "rec.webm.mux", qos: .userInitiated)
    private let audio: (pipeline: MixedAudioPipeline, opus: OpusAudioEncoder)?
    private let audioLock = NSLock()
    private let failure = FirstFailure()
    private let lifecycle = SinkLifecycle()

    init(url: URL, config: VideoEncodeConfig) throws {
        encoder = try SvtAv1Encoder(config: config)
        audio = config.audioSources.isEmpty
            ? nil
            : (MixedAudioPipeline(sources: config.audioSources), try OpusAudioEncoder())
        muxer = try WebMMuxer(
            url: url,
            video: .init(width: config.width, height: config.height,
                         codecPrivate: encoder.codecConfiguration,
                         nominalFrameDurationMilliseconds: Int64(1_000 / max(config.frameRate, 1))),
            includesAudio: audio != nil)
        encoder.start(
            onPacket: { [muxer, muxQueue, failure] packet in
                muxQueue.async { Self.mux(failure) { try muxer.addVideo(packet) } }
            },
            onError: { [failure] error in failure.record(error) })
    }

    func appendVideo(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) throws {
        try lifecycle.ensureRecording()
        try failure.throwIfFailed()
        try encoder.encode(pixelBuffer, ptsMilliseconds: try presentationTime.milliseconds())
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer, source: AudioSource) throws {
        try lifecycle.ensureRecording()
        try failure.throwIfFailed()
        guard let audio else { return }
        let packets = try audioLock.withLock {
            guard let mixed = try audio.pipeline.process(sampleBuffer, from: source) else { return [EncodedAudioPacket]() }
            return try audio.opus.encode(mixed)
        }
        enqueueAudio(packets)
    }

    func finish() async throws {
        try lifecycle.beginFinishing()
        await encoder.finish()
        if let audio {
            do {
                let packets = try audioLock.withLock {
                    let tail = try audio.pipeline.flush().map(audio.opus.encode) ?? []
                    return tail + (try audio.opus.flush())
                }
                enqueueAudio(packets)
            } catch {
                failure.record(error)
            }
        }
        // Finalize even after a failure so whatever was recorded stays playable.
        let finalizeError: Error? = await withCheckedContinuation { continuation in
            muxQueue.async { [muxer] in
                do {
                    try muxer.finish()
                    continuation.resume(returning: nil)
                } catch {
                    continuation.resume(returning: error)
                }
            }
        }
        if let finalizeError { failure.record(finalizeError) }
        try failure.throwIfFailed()
    }

    func cancel() {
        guard lifecycle.cancel() else { return }
        encoder.cancel(whenStopped: { [muxer] in muxer.abort() }, on: muxQueue)
    }

    private func enqueueAudio(_ packets: [EncodedAudioPacket]) {
        guard !packets.isEmpty else { return }
        muxQueue.async { [muxer, failure] in
            Self.mux(failure) { for packet in packets { try muxer.addAudio(packet) } }
        }
    }

    /// Runs a mux step unless an earlier one failed: after an I/O error further writes are pointless.
    private static func mux(_ failure: FirstFailure, _ step: () throws -> Void) {
        guard failure.current == nil else { return }
        do { try step() } catch { failure.record(error) }
    }
}
