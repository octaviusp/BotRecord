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

    private static func roundedToEven(_ value: CGFloat) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }
}
