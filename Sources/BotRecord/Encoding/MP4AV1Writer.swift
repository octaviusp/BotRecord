import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// AV1 (SVT-AV1) + AAC in MP4. AV1 packets go through AVAssetWriter untouched (passthrough);
/// audio is mixed to stereo PCM and AVAssetWriter encodes it to AAC.
///
/// Threads: `append*` on the capture queue, video packets on the encoder thread, every
/// AVAssetWriter call on a private serial queue, `finish`/`cancel` from the main actor.
final class MP4AV1Writer: MediaSink, @unchecked Sendable {
    /// AVAssetWriter accepts AV1 passthrough samples on macOS 26 (verified by the encoding harness).
    static var isSupported: Bool { true }

    var droppedFrames: Int { encoder.droppedFrames }

    private let url: URL
    private let encoder: SvtAv1Encoder
    private let samples: AV1SampleBufferFactory
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let audioPipeline: MixedAudioPipeline?
    private let nominalFrameDurationMilliseconds: Int64
    private let writerQueue = DispatchQueue(label: "rec.mp4-av1.writer", qos: .userInitiated)
    private let audioLock = NSLock()
    private let failure = FirstFailure()
    private let lifecycle = SinkLifecycle()

    // Confined to `writerQueue`.
    /// Held back one packet so each sample gets its real (variable) duration.
    private var heldVideoPacket: EncodedVideoPacket?
    private var pendingVideo: [CMSampleBuffer] = []
    private var pendingAudio: [CMSampleBuffer] = []

    init(url: URL, config: VideoEncodeConfig) throws {
        self.url = url
        nominalFrameDurationMilliseconds = Int64(1_000 / max(config.frameRate, 1))
        encoder = try SvtAv1Encoder(config: config)
        samples = try AV1SampleBufferFactory(width: config.width, height: config.height,
                                             codecConfiguration: encoder.codecConfiguration)
        try? FileManager.default.removeItem(at: url) // AVAssetWriter refuses to overwrite; absence is fine
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw EncodingError.fileWrite(url, underlying: error)
        }
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: samples.videoFormat)
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw EncodingError.unsupported("This Mac can't write AV1 video into MP4. Choose WebM instead.")
        }
        writer.add(videoInput)

        if config.audioSources.isEmpty {
            audioInput = nil
            audioPipeline = nil
        } else {
            let aac = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: StereoPCMChunk.sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ], sourceFormatHint: samples.audioFormat)
            aac.expectsMediaDataInRealTime = true
            guard writer.canAdd(aac) else { throw EncodingError.encoderSetup("cannot add an AAC track to the MP4") }
            writer.add(aac)
            audioInput = aac
            audioPipeline = MixedAudioPipeline(sources: config.audioSources)
        }

        guard writer.startWriting() else {
            throw EncodingError.fileWrite(url, underlying: writer.error ?? CocoaError(.fileWriteUnknown))
        }
        writer.startSession(atSourceTime: .zero)
        encoder.start(
            onPacket: { [self] packet in writerQueue.async { self.receive(packet) } },
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
        guard let audioPipeline else { return }
        let mixed = try audioLock.withLock { try audioPipeline.process(sampleBuffer, from: source) }
        if let mixed { try enqueueAudio(mixed) }
    }

    func finish() async throws {
        try lifecycle.beginFinishing()
        await encoder.finish()
        if let audioPipeline, let tail = audioLock.withLock({ audioPipeline.flush() }) {
            do { try enqueueAudio(tail) } catch { failure.record(error) }
        }
        await withCheckedContinuation { continuation in
            writerQueue.async { [self] in
                releaseHeldVideo(durationMilliseconds: nominalFrameDurationMilliseconds)
                drainPending(waitUntilEmpty: true)
                videoInput.markAsFinished()
                audioInput?.markAsFinished()
                continuation.resume()
            }
        }
        // Finalize even after a failure so whatever was recorded stays playable.
        await writer.finishWriting()
        if writer.status == .failed {
            failure.record(EncodingError.fileWrite(url, underlying: writer.error ?? CocoaError(.fileWriteUnknown)))
        }
        try failure.throwIfFailed()
    }

    func cancel() {
        guard lifecycle.cancel() else { return }
        encoder.cancel(whenStopped: { [self] in
            if writer.status == .writing { writer.cancelWriting() }
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // cancelWriting already removed it
            } catch {
                failure.record(EncodingError.fileWrite(url, underlying: error))
            }
        }, on: writerQueue)
    }

    // MARK: - Writer queue

    private func enqueueAudio(_ chunk: StereoPCMChunk) throws {
        let sample = try samples.audioSample(chunk)
        writerQueue.async { [self] in
            pendingAudio.append(sample)
            drainPending(waitUntilEmpty: false)
        }
    }

    private func receive(_ packet: EncodedVideoPacket) {
        if let held = heldVideoPacket {
            releaseHeldVideo(durationMilliseconds: max(packet.ptsMilliseconds - held.ptsMilliseconds, 1))
        }
        heldVideoPacket = packet
        drainPending(waitUntilEmpty: false)
    }

    private func releaseHeldVideo(durationMilliseconds: Int64) {
        guard let held = heldVideoPacket else { return }
        heldVideoPacket = nil
        do {
            pendingVideo.append(try samples.videoSample(held, durationMilliseconds: durationMilliseconds))
        } catch {
            failure.record(error)
        }
    }

    /// Appends what each input accepts now. Real-time inputs rarely push back; at the end we wait for them.
    private func drainPending(waitUntilEmpty: Bool) {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            guard writer.status == .writing else {
                if writer.status == .failed {
                    failure.record(EncodingError.fileWrite(url, underlying: writer.error ?? CocoaError(.fileWriteUnknown)))
                }
                pendingVideo.removeAll()
                pendingAudio.removeAll()
                return
            }
            append(&pendingVideo, to: videoInput)
            if let audioInput { append(&pendingAudio, to: audioInput) }
            if !waitUntilEmpty || (pendingVideo.isEmpty && pendingAudio.isEmpty) { return }
            Thread.sleep(forTimeInterval: 0.005)
        } while Date() < deadline
        failure.record(EncodingError.encoderFailure("the MP4 writer stopped accepting samples"))
    }

    private func append(_ queue: inout [CMSampleBuffer], to input: AVAssetWriterInput) {
        var appended = 0
        for sample in queue {
            guard input.isReadyForMoreMediaData else { break }
            guard input.append(sample) else { break } // writer.status turns .failed; reported on the next drain
            appended += 1
        }
        queue.removeFirst(appended)
    }
}
