import CoreGraphics

enum CaptureGeometry {
    struct PixelSize: Equatable {
        let width: Int
        let height: Int

        var cgSize: CGSize { CGSize(width: width, height: height) }
    }

    /// Scales the captured region so its height matches `targetHeight` without ever upscaling past the
    /// region's native pixel size (upscaling only inflates the bitrate). Both sides come out even because
    /// 4:2:0 chroma and every encoder require it.
    static func outputSize(regionInPoints: CGSize, pointPixelScale: CGFloat, targetHeight: Int) -> PixelSize {
        let nativeWidth = regionInPoints.width * pointPixelScale
        let nativeHeight = regionInPoints.height * pointPixelScale
        let height = min(CGFloat(targetHeight), nativeHeight)
        let width = nativeWidth * height / nativeHeight
        return PixelSize(width: roundedToEven(width), height: roundedToEven(height))
    }

    /// WhatsApp re-encodes every video it is sent: "HD" tops out at 1280 px on the long edge, "Standard" at 848.
    /// Handing it exactly that box (short edge on its 16 px macroblock grid, as its own output uses) means it
    /// never has to resample our frames a second time, which measured as the largest avoidable softening.
    static let whatsAppHDLongEdge = 1280

    /// Size of the H.264 copy made for chat apps: `size` fitted into the HD box, never upscaled.
    static func whatsAppSize(fitting size: PixelSize) -> PixelSize {
        let longEdge = max(size.width, size.height)
        guard longEdge > whatsAppHDLongEdge else { return size }
        let scale = CGFloat(whatsAppHDLongEdge) / CGFloat(longEdge)
        return PixelSize(
            width: roundedToMultiple(of: 16, CGFloat(size.width) * scale),
            height: roundedToMultiple(of: 16, CGFloat(size.height) * scale)
        )
    }

    private static func roundedToEven(_ value: CGFloat) -> Int {
        roundedToMultiple(of: 2, value)
    }

    private static func roundedToMultiple(of step: Int, _ value: CGFloat) -> Int {
        max(step, Int((value / CGFloat(step)).rounded()) * step)
    }
}
