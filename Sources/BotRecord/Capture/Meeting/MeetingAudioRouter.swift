import CoreMedia
import Foundation

/// Everything that runs on the meeting's audio queue: mapping both sources onto the recording
/// timeline, encoding them as separate tracks of `audio.webm`, the live transcription taps, and the
/// voice mix sent to the optional video. All mutable state is confined to `queue`.
final class MeetingAudioRouter: @unchecked Sendable {
    /// Silence is only committed this far behind real time, so audio still in flight is never "late".
    private static let heartbeatLagSeconds = 0.5
    private static let heartbeatInterval = DispatchTimeInterval.milliseconds(250)
    /// The mic tap arrives ~100 ms after ScreenCaptureKit audio and a silent app is only advanced by
    /// the heartbeat, so the video mix waits up to a second for the slower source before padding it.
    private static let videoMixMaxLagFrames = Int64(StereoPCMChunk.sampleRate)

    let queue = DispatchQueue(label: "\(AppPaths.identifier).meeting-audio", qos: .userInitiated)

    private let clock: RecordingClock
    private let writer: MultiTrackAudioWriter
    private let trackIndices: [MeetingTrack: Int]
    private let taps: [MeetingTrack: TranscriptionTap]
    private let video: (writer: WebMAV1Writer, mix: AudioMixer)?
    private let onError: @Sendable (Error) -> Void
    private let systemConverter = StereoPCMConverter()
    private var microphoneResampler: MonoResampler?
    private var heartbeat: DispatchSourceTimer?
    private var isClosed = false

    /// - Parameter tracks: the writer's tracks, in its order.
    init(writer: MultiTrackAudioWriter, tracks: [MeetingTrack], clock: RecordingClock, observers: LiveAudioObserverSlot,
         videoWriter: WebMAV1Writer?, onError: @escaping @Sendable (Error) -> Void) throws {
        self.writer = writer
        self.clock = clock
        self.onError = onError
        trackIndices = Dictionary(uniqueKeysWithValues: tracks.enumerated().map { ($1, $0) })
        taps = Dictionary(uniqueKeysWithValues: try tracks.map { ($0, try TranscriptionTap(track: $0, slot: observers)) })
        video = videoWriter.map { writer in
            (writer, AudioMixer(sources: Set(tracks.map { Self.mixSource(for: $0) }), maxLagFrames: Self.videoMixMaxLagFrames))
        }
    }

    func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.heartbeatInterval, repeating: Self.heartbeatInterval)
        timer.setEventHandler { [weak self] in self?.advanceSilentTracks() }
        timer.resume()
        queue.async { self.heartbeat = timer }
    }

    // MARK: Input

    /// ScreenCaptureKit audio ("Others"). Runs on `queue`.
    func receiveSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isClosed, let time = clock.audioTime(for: sampleBuffer.presentationTimeStamp) else { return }
        perform {
            let chunk = try systemConverter.convert(try sampleBuffer.shiftingTimestamps(to: time))
            try commit(chunk, to: .others)
        }
    }

    /// Microphone audio ("Me"). Called on the audio render thread: only hands the buffer off.
    func receiveMicrophone(_ buffer: MicrophoneCapture.Buffer) {
        queue.async { self.processMicrophone(buffer) }
    }

    private func processMicrophone(_ buffer: MicrophoneCapture.Buffer) {
        let hostTime = CMClockMakeHostTimeFromSystemUnits(buffer.hostTime)
        guard !isClosed, let time = clock.audioTime(for: hostTime) else { return }
        perform {
            let mono = try microphoneResampler(for: buffer.sampleRate).resample(buffer.samples)
            var stereo = [Float](repeating: 0, count: mono.count * 2)
            for (index, sample) in mono.enumerated() {
                stereo[index * 2] = sample
                stereo[index * 2 + 1] = sample
            }
            let startFrame = Int64((time.seconds * Double(StereoPCMChunk.sampleRate)).rounded())
            try commit(StereoPCMChunk(samples: stereo, startFrame: startFrame), to: .me)
        }
    }

    /// A new device may run at another rate; restarting the filter at that point is inaudible.
    private func microphoneResampler(for rate: Double) throws -> MonoResampler {
        if let microphoneResampler, microphoneResampler.inputRate == rate { return microphoneResampler }
        let resampler = try MonoResampler(inputRate: rate, outputRate: Double(StereoPCMChunk.sampleRate))
        microphoneResampler = resampler
        return resampler
    }

    // MARK: Lifecycle

    /// Pads every track to `finalFrame`, flushes the taps and the video mix, and finalizes `audio.webm`.
    /// Runs even after a failure, so whatever was captured stays playable. Returns the finalize error.
    func finish(through finalFrame: Int64) async -> Error? {
        await onQueue {
            self.heartbeat?.cancel()
            self.isClosed = true
            do {
                try self.forward(try self.writer.advance(to: finalFrame))
                try self.forward(try self.writer.finish())
                self.taps.values.forEach { $0.flush() }
                if let video = self.video, let tail = video.mix.flush() {
                    try video.writer.appendAudio(tail, source: .system)
                }
                return nil
            } catch {
                return error
            }
        }
    }

    /// Stops processing and deletes `audio.webm`.
    func cancel() async {
        await onQueue {
            self.heartbeat?.cancel()
            self.isClosed = true
            self.writer.cancel()
        }
    }

    // MARK: Routing

    /// Keeps tracks advancing while an app is silent (ScreenCaptureKit then sends nothing), so the
    /// muxer can interleave and nothing piles up in memory during a long meeting.
    private func advanceSilentTracks() {
        guard !isClosed else { return }
        let seconds = clock.elapsedTime(at: RecordingClock.hostNow).seconds - Self.heartbeatLagSeconds
        guard seconds > 0 else { return }
        perform { try forward(try writer.advance(to: Int64(seconds * Double(StereoPCMChunk.sampleRate)))) }
    }

    private func commit(_ chunk: StereoPCMChunk, to track: MeetingTrack) throws {
        guard let index = trackIndices[track], let committed = try writer.append(chunk, toTrack: index) else { return }
        try route(committed, from: track)
    }

    /// Routes per-track output of the writer, indexed like its tracks.
    private func forward(_ committedByTrack: [StereoPCMChunk?]) throws {
        for (track, index) in trackIndices {
            if let committed = committedByTrack[index] { try route(committed, from: track) }
        }
    }

    /// Sends audio exactly as written to the file on to transcription and the video's voice mix.
    private func route(_ committed: StereoPCMChunk, from track: MeetingTrack) throws {
        try taps[track]?.consume(committed)
        guard let video else { return }
        video.mix.append(committed, from: Self.mixSource(for: track))
        if let mixed = video.mix.drain() { try video.writer.appendAudio(mixed, source: .system) }
    }

    /// Stops feeding everything after the first error; the recorder finalizes and reports it once.
    private func perform(_ step: () throws -> Void) {
        do {
            try step()
        } catch {
            isClosed = true
            heartbeat?.cancel()
            onError(error)
        }
    }

    private func onQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private static func mixSource(for track: MeetingTrack) -> AudioSource {
        track == .me ? .microphone : .system
    }
}
