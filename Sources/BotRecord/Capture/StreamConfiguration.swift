import CoreGraphics
import ScreenCaptureKit

/// Everything derived from a target and the user's options before the stream exists.
struct StreamSetup {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
    let outputSize: CaptureGeometry.PixelSize
}

enum StreamConfiguration {
    static let audioSampleRate = 48_000
    static let audioChannelCount = 2
    private static let queueDepth = 6

    /// Captures `display` minus this app's own windows, so overlays and the HUD never reach the video.
    static func make(
        display: SCDisplay,
        sourceRect: CGRect?,
        excluding ownApplications: [SCRunningApplication],
        options: RecordingOptions
    ) throws -> StreamSetup {
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let displayBounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let region = sourceRect.map { $0.intersection(displayBounds) } ?? displayBounds
        guard !region.isNull, region.width >= 1, region.height >= 1 else { throw CaptureError.invalidCaptureRegion }

        let outputSize = CaptureGeometry.outputSize(
            regionInPoints: region.size,
            pointPixelScale: CGFloat(filter.pointPixelScale),
            targetHeight: options.resolution.rawValue
        )

        let configuration = SCStreamConfiguration()
        if sourceRect != nil { configuration.sourceRect = region }
        configuration.width = outputSize.width
        configuration.height = outputSize.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.frameRate.rawValue))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.colorMatrix = CGDisplayStream.yCbCrMatrix_ITU_R_709_2
        configuration.showsCursor = options.showCursor
        configuration.showMouseClicks = options.highlightClicks
        configuration.queueDepth = queueDepth
        configuration.capturesAudio = options.captureSystemAudio
        configuration.captureMicrophone = options.captureMicrophone
        configuration.sampleRate = audioSampleRate
        configuration.channelCount = audioChannelCount
        configuration.excludesCurrentProcessAudio = true
        return StreamSetup(filter: filter, configuration: configuration, outputSize: outputSize)
    }
}
