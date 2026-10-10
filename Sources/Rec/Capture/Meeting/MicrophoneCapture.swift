import AVFoundation

/// The user's microphone through AVAudioEngine (the "Me" track).
///
/// With echo cancellation the input runs through Apple's voice processing, which removes the call
/// audio the speakers leak into the mic; ducking of other audio is kept to the minimum so the call
/// stays audible. A device change (AirPods in or out) stops the engine, so the tap is reinstalled on
/// the new default device. Buffers carry host times, so the timeline survives the gap.
@MainActor
final class MicrophoneCapture {
    struct Buffer: Sendable {
        /// First channel only: voice processing writes the processed voice there, and speech needs no stereo.
        let samples: [Float]
        let sampleRate: Double
        /// Host time (mach units) of the first sample.
        let hostTime: UInt64
    }

    /// 100 ms at 48 kHz: small enough for live transcription, large enough to keep wake-ups rare.
    private static let tapBufferFrames: AVAudioFrameCount = 4_800
    private static let restartAttempts = 3
    private static let restartDelay = Duration.milliseconds(500)

    private let engine = AVAudioEngine()
    private let echoCancellation: Bool
    private let onBuffer: @Sendable (Buffer) -> Void
    private let onLost: @MainActor (Error) -> Void
    private var configurationObserver: NSObjectProtocol?
    private var isRunning = false
    private var isRestarting = false

    /// - Parameters:
    ///   - onBuffer: called on the audio render thread; must only hand the buffer off.
    ///   - onLost: no input device came back after a device change.
    init(echoCancellation: Bool, onBuffer: @escaping @Sendable (Buffer) -> Void, onLost: @escaping @MainActor (Error) -> Void) {
        self.echoCancellation = echoCancellation
        self.onBuffer = onBuffer
        self.onLost = onLost
    }

    static func requestPermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw CaptureError.microphonePermissionDenied }
        default:
            throw CaptureError.microphonePermissionDenied
        }
    }

    func start() throws {
        try configureVoiceProcessing()
        try startTap()
        isRunning = true
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.restartAfterConfigurationChange() }
        }
    }

    func stop() {
        isRunning = false
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }

    // MARK: Engine

    private func configureVoiceProcessing() throws {
        let input = engine.inputNode
        if input.isVoiceProcessingEnabled != echoCancellation {
            try input.setVoiceProcessingEnabled(echoCancellation)
        }
        if echoCancellation {
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
    }

    private func startTap() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.microphoneUnavailable }
        input.installTap(onBus: 0, bufferSize: Self.tapBufferFrames, format: format, block: Self.tapBlock(onBuffer))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func restartAfterConfigurationChange() async {
        guard isRunning, !isRestarting else { return }
        isRestarting = true
        defer { isRestarting = false }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)

        for attempt in 1...Self.restartAttempts {
            do {
                try configureVoiceProcessing()
                try startTap()
                captureLog.info("Microphone restarted after a device change")
                return
            } catch {
                captureLog.error("Microphone restart \(attempt) failed: \(error.localizedDescription)")
            }
            do {
                try await Task.sleep(for: Self.restartDelay)
            } catch {
                return // cancelled: the recording is shutting down
            }
            guard isRunning else { return }
        }
        stop()
        onLost(CaptureError.microphoneLost)
    }

    /// Built outside the main actor: the engine calls it on its render thread.
    nonisolated private static func tapBlock(_ onBuffer: @escaping @Sendable (Buffer) -> Void) -> AVAudioNodeTapBlock {
        { buffer, time in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let frameCount = Int(buffer.frameLength)
            let stride = buffer.stride
            let samples = stride == 1
                ? Array(UnsafeBufferPointer(start: channel, count: frameCount))
                : (0..<frameCount).map { channel[$0 * stride] }
            let sampleRate = buffer.format.sampleRate
            let hostTime = time.isHostTimeValid
                ? time.hostTime
                : mach_absolute_time() - AVAudioTime.hostTime(forSeconds: Double(frameCount) / sampleRate)
            onBuffer(Buffer(samples: samples, sampleRate: sampleRate, hostTime: hostTime))
        }
    }
}
