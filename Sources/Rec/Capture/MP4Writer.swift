import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

enum MP4WriterError: LocalizedError, CustomNSError {
    case cannotStart(underlying: Error?)
    case writerFailed(underlying: Error?)
    case noFramesRecorded
    case notWriting

    var errorDescription: String? {
        switch self {
        case .cannotStart(let underlying): "The MP4 file could not be created: \(Self.detail(underlying))"
        case .writerFailed(let underlying): "The MP4 file could not be written: \(Self.detail(underlying))"
        case .noFramesRecorded: "No video frames were recorded."
        case .notWriting: "The MP4 file is already closed."
        }
    }

    /// Lets `FailureMessage` recognise causes such as a full disk behind the wrapper.
    var errorUserInfo: [String: Any] {
        switch self {
        case .cannotStart(let underlying?), .writerFailed(let underlying?): [NSUnderlyingErrorKey: underlying]
        default: [:]
        }
    }

    private static func detail(_ error: Error?) -> String {
        error?.localizedDescription ?? "unknown error"
    }
}

/// Hardware H.264 MP4 writer. Appends ScreenCaptureKit's IOSurface-backed buffers as they are, so the
/// pixels go straight to the media engine without a CPU copy.
final class MP4Writer: MediaSink {
    private static let referenceBitsPerPixelPerFrame = 6_000_000.0 / (1920 * 1080 * 60)
    private static let minimumBitrate = 1_500_000
    private static let audioBitrate = 128_000
    private static let keyFrameInterval: TimeInterval = 2
    /// Finer than the 600 default so 60 fps frame times stay exact.
    private static let videoTimescale: CMTimeScale = 90_000
    /// How long a full encoder queue may stall the capture queue before the frame is dropped.
    private static let readinessTimeout: Duration = .milliseconds(50)

    private enum State { case writing, finished, cancelled }

    private let url: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInputs: [AudioSource: AVAssetWriterInput]
    private var state = State.writing
    private var appendedVideoFrames = 0
    private var droppedVideoFrames = 0

    init(url: URL, config: VideoEncodeConfig, includeAudio: Bool) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings(for: config))
        videoInput.expectsMediaDataInRealTime = true
        videoInput.mediaTimeScale = Self.videoTimescale
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: config.width,
                kCVPixelBufferHeightKey as String: config.height,
            ]
        )
        writer.add(videoInput)

        var audioInputs: [AudioSource: AVAssetWriterInput] = [:]
        if includeAudio {
            for source in config.audioSources {
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
                input.expectsMediaDataInRealTime = true
                writer.add(input)
                audioInputs[source] = input
            }
        }
        self.audioInputs = audioInputs

        guard writer.startWriting() else { throw MP4WriterError.cannotStart(underlying: writer.error) }
        writer.startSession(atSourceTime: .zero)
    }

    func appendVideo(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) throws {
        try ensureWriting()
        guard waitUntilReady(videoInput) else {
            droppedVideoFrames += 1
            return
        }
        guard pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
            throw MP4WriterError.writerFailed(underlying: writer.error)
        }
        appendedVideoFrames += 1
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer, source: AudioSource) throws {
        try ensureWriting()
        guard let input = audioInputs[source] else { return }
        guard waitUntilReady(input) else {
            captureLog.error("MP4 audio buffer dropped: encoder not ready")
            return
        }
        guard input.append(sampleBuffer) else {
            throw MP4WriterError.writerFailed(underlying: writer.error)
        }
    }

    func finish() async throws {
        guard state == .writing else { throw MP4WriterError.notWriting }
        state = .finished
        guard appendedVideoFrames > 0 else {
            writer.cancelWriting()
            removeFile()
            throw MP4WriterError.noFramesRecorded
        }
        if droppedVideoFrames > 0 {
            captureLog.error("MP4 writer dropped \(self.droppedVideoFrames) video frames: encoder not ready")
        }
        videoInput.markAsFinished()
        audioInputs.values.forEach { $0.markAsFinished() }
        await writer.finishWriting()
        guard writer.status == .completed else { throw MP4WriterError.writerFailed(underlying: writer.error) }
    }

    func cancel() {
        guard state == .writing else { return }
        state = .cancelled
        writer.cancelWriting()
        removeFile()
    }

    private func ensureWriting() throws {
        guard state == .writing else { throw MP4WriterError.notWriting }
        if writer.status == .failed { throw MP4WriterError.writerFailed(underlying: writer.error) }
    }

    private func removeFile() {
        OutputFiles.removeIfPresent(url)
    }

    /// Real-time inputs report "not ready" only when the encoder is saturated; waiting a few
    /// milliseconds keeps the frame, and the capture stream's own queue absorbs the stall.
    private func waitUntilReady(_ input: AVAssetWriterInput) -> Bool {
        let deadline = ContinuousClock.now + Self.readinessTimeout
        while !input.isReadyForMoreMediaData {
            guard ContinuousClock.now < deadline, writer.status == .writing else { return false }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return true
    }

    static func bitrate(width: Int, height: Int, frameRate: Int) -> Int {
        max(minimumBitrate, Int(Double(width * height * frameRate) * referenceBitsPerPixelPerFrame))
    }

    private static func videoSettings(for config: VideoEncodeConfig) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate(width: config.width, height: config.height, frameRate: config.frameRate),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                AVVideoMaxKeyFrameIntervalDurationKey: keyFrameInterval,
                AVVideoExpectedSourceFrameRateKey: config.frameRate,
                // No B-frames: presentation order equals decode order, which keeps live encoding latency flat.
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
    }

    private static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: audioBitrate,
    ]
}
