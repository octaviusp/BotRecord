import CoreGraphics
import CoreMedia
import CoreVideo
import VideoToolbox

/// Keeps one preview image per recording without converting every frame: the frame at about one second,
/// or for shorter recordings the latest of a few refreshes taken during the first second.
/// Used only from the capture queue.
final class Thumbnailer {
    private static let targetTime = CMTime(seconds: 1, preferredTimescale: 600)
    private static let refreshInterval = CMTime(seconds: 0.25, preferredTimescale: 600)
    private static let maxWidth = 640

    private(set) var image: CGImage?
    private var lastCaptureTime: CMTime?

    func offer(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        if let last = lastCaptureTime {
            guard last < Self.targetTime, time >= Self.targetTime || time - last >= Self.refreshInterval else { return }
        }
        guard let captured = Self.makeImage(from: pixelBuffer) else { return }
        image = captured
        lastCaptureTime = time
    }

    private static func makeImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        var fullSize: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &fullSize)
        guard status == noErr, let fullSize else {
            captureLog.error("Thumbnail conversion failed with status \(status)")
            return nil
        }
        return downscaled(fullSize)
    }

    private static func downscaled(_ image: CGImage) -> CGImage? {
        guard image.width > maxWidth else { return image }
        let height = max(1, image.height * maxWidth / image.width)
        guard let context = CGContext(
            data: nil, width: maxWidth, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            captureLog.error("Thumbnail context could not be created")
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
        return context.makeImage()
    }
}
