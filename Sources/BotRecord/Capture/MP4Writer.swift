import Accelerate
import AVFoundation
import CoreMedia
import CoreVideo
import VideoToolbox

enum MP4WriterError: LocalizedError, CustomNSError {
    case cannotStart(underlying: Error?)
    case writerFailed(underlying: Error?)
    case noFramesRecorded
    case notWriting
    case scalingFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .cannotStart(let underlying): "The MP4 file could not be created: \(Self.detail(underlying))"
        case .writerFailed(let underlying): "The MP4 file could not be written: \(Self.detail(underlying))"
        case .noFramesRecorded: "No video frames were recorded."
        case .notWriting: "The MP4 file is already closed."
        case .scalingFailed(let detail): "A video frame could not be resized for the MP4 file: \(detail)"
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

/// Hardware H.264 MP4 writer. A recording appends ScreenCaptureKit's IOSurface-backed buffers as they are,
/// so the pixels go straight to the media engine without a CPU copy.
final class MP4Writer: MediaSink {
    enum Purpose {
        /// The user's chosen output, written at the capture size.
        case recording
        /// The copy for chat apps (WhatsApp, iMessage): fitted to WhatsApp's HD box and resized here with a
        /// Lanczos filter, because WhatsApp would otherwise resample it again with a softer bilinear one.
        case chatCopy
    }

    private static let referenceBitsPerPixelPerFrame = 6_000_000.0 / (1920 * 1080 * 60)
    /// 4 Mbps for a 1280x800 frame at 60 fps. WhatsApp re-encodes at about 2.5 Mbps whatever it receives, so this
    /// only matters when the file travels untouched (sent as a document, AirDrop, iMessage).
    private static let chatCopyBitsPerPixelPerFrame = 4_000_000.0 / (1280 * 800 * 60)
    private static let minimumBitrate = 1_500_000
    private static let minimumChatCopyBitrate = 3_000_000
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
    /// Only set when the file's size differs from the size of the captured frames.
    private let scaler: LanczosFrameScaler?
    private let audioInputs: [AudioSource: AVAssetWriterInput]
    private var state = State.writing
    private var appendedVideoFrames = 0
    private var droppedVideoFrames = 0

    init(url: URL, config: VideoEncodeConfig, includeAudio: Bool, purpose: Purpose = .recording) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let capturedSize = CaptureGeometry.PixelSize(width: config.width, height: config.height)
        let fileSize = purpose == .chatCopy ? CaptureGeometry.whatsAppSize(fitting: capturedSize) : capturedSize
        scaler = fileSize == capturedSize ? nil : LanczosFrameScaler(outputSize: fileSize)

        videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: Self.videoSettings(for: config, fileSize: fileSize, purpose: purpose)
        )
        videoInput.expectsMediaDataInRealTime = true
        videoInput.mediaTimeScale = Self.videoTimescale
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: fileSize.width,
                kCVPixelBufferHeightKey as String: fileSize.height,
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
        let frame = try scaler?.scaled(pixelBuffer) ?? pixelBuffer
        guard pixelBufferAdaptor.append(frame, withPresentationTime: presentationTime) else {
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

    static func bitrate(width: Int, height: Int, frameRate: Int, purpose: Purpose = .recording) -> Int {
        let pixelsPerSecond = Double(width * height * frameRate)
        switch purpose {
        case .recording: return max(minimumBitrate, Int(pixelsPerSecond * referenceBitsPerPixelPerFrame))
        case .chatCopy: return max(minimumChatCopyBitrate, Int(pixelsPerSecond * chatCopyBitsPerPixelPerFrame))
        }
    }

    private static func videoSettings(
        for config: VideoEncodeConfig,
        fileSize: CaptureGeometry.PixelSize,
        purpose: Purpose
    ) -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: fileSize.width,
            AVVideoHeightKey: fileSize.height,
            AVVideoEncoderSpecificationKey: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate(
                    width: fileSize.width, height: fileSize.height, frameRate: config.frameRate, purpose: purpose
                ),
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

/// Downscales 8-bit 4:2:0 biplanar frames with vImage's Lanczos resampler. ScreenCaptureKit and AVAssetWriter
/// both resize bilinearly, which measurably softens small UI text; Lanczos keeps its edges.
private final class LanczosFrameScaler {
    private let outputSize: CaptureGeometry.PixelSize
    private var pool: CVPixelBufferPool?
    private var scratch: UnsafeMutableRawPointer?
    private var scratchSourceSize: CaptureGeometry.PixelSize?

    init(outputSize: CaptureGeometry.PixelSize) {
        self.outputSize = outputSize
    }

    deinit {
        scratch?.deallocate()
    }

    func scaled(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        let sourceSize = CaptureGeometry.PixelSize(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source))
        let destination = try makeDestination()
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(destination, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        var luma = try planes(source, destination, index: 0)
        var chroma = try planes(source, destination, index: 1)
        try prepareScratch(for: sourceSize, luma: &luma, chroma: &chroma)
        try check(vImageScale_Planar8(&luma.source, &luma.destination, scratch, Self.flags), "luma")
        try check(vImageScale_CbCr8(&chroma.source, &chroma.destination, scratch, Self.flags), "chroma")
        // The writer's colour tags come from its settings, but VideoToolbox also reads the buffer's own.
        CVBufferPropagateAttachments(source, destination)
        return destination
    }

    private static let flags = vImage_Flags(kvImageHighQualityResampling)

    private typealias PlanePair = (source: vImage_Buffer, destination: vImage_Buffer)

    private func planes(_ source: CVPixelBuffer, _ destination: CVPixelBuffer, index: Int) throws -> PlanePair {
        guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, index),
              let destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, index) else {
            throw MP4WriterError.scalingFailed(detail: "frame has no readable plane \(index)")
        }
        func buffer(_ pixelBuffer: CVPixelBuffer, _ base: UnsafeMutableRawPointer) -> vImage_Buffer {
            vImage_Buffer(
                data: base,
                height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(pixelBuffer, index)),
                width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(pixelBuffer, index)),
                rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, index)
            )
        }
        return (buffer(source, sourceBase), buffer(destination, destinationBase))
    }

    /// vImage needs working memory sized for the exact source and destination; the frame size never changes
    /// mid-recording, so one allocation serves every frame.
    private func prepareScratch(for sourceSize: CaptureGeometry.PixelSize, luma: inout PlanePair, chroma: inout PlanePair) throws {
        guard scratchSourceSize != sourceSize else { return }
        let lumaBytes = vImageScale_Planar8(&luma.source, &luma.destination, nil, Self.flags | vImage_Flags(kvImageGetTempBufferSize))
        let chromaBytes = vImageScale_CbCr8(&chroma.source, &chroma.destination, nil, Self.flags | vImage_Flags(kvImageGetTempBufferSize))
        try check(min(lumaBytes, chromaBytes), "scratch size")
        scratch?.deallocate()
        scratch = UnsafeMutableRawPointer.allocate(byteCount: max(lumaBytes, chromaBytes), alignment: 64)
        scratchSourceSize = sourceSize
    }

    private func makeDestination() throws -> CVPixelBuffer {
        if pool == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: outputSize.width,
                kCVPixelBufferHeightKey as String: outputSize.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
            ]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        var buffer: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
            throw MP4WriterError.scalingFailed(detail: "no buffer available in the resize pool")
        }
        return buffer
    }

    private func check(_ status: vImage_Error, _ step: String) throws {
        guard status >= 0 else { throw MP4WriterError.scalingFailed(detail: "vImage \(step) error \(status)") }
    }
}
