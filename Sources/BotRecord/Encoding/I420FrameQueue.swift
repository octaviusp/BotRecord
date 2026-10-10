import Accelerate
import CoreVideo
import Foundation

/// One planar 8-bit 4:2:0 picture owned by the pool, plus its timestamp.
final class I420Frame {
    let width: Int
    let height: Int
    let luma: UnsafeMutablePointer<UInt8>
    let cb: UnsafeMutablePointer<UInt8>
    let cr: UnsafeMutablePointer<UInt8>
    var ptsMilliseconds: Int64 = 0

    var chromaWidth: Int { width / 2 }
    var chromaHeight: Int { height / 2 }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        luma = .allocate(capacity: width * height)
        cb = .allocate(capacity: width * height / 4)
        cr = .allocate(capacity: width * height / 4)
    }

    deinit {
        luma.deallocate()
        cb.deallocate()
        cr.deallocate()
    }

    /// Copies an NV12 (`420v`) buffer, deinterleaving CbCr with vImage (vectorized).
    func copy(fromNV12 pixelBuffer: CVPixelBuffer) throws {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) == width,
              CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) == height
        else {
            throw EncodingError.encoderFailure(
                "expected \(width)x\(height) 420v frames, got \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { throw EncodingError.encoderFailure("pixel buffer has no base address") }

        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let lumaSource = lumaBase.assumingMemoryBound(to: UInt8.self)
        for row in 0..<height {
            (luma + row * width).update(from: lumaSource + row * lumaStride, count: width)
        }

        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        var cbBuffer = vImage_Buffer(data: cb, height: vImagePixelCount(chromaHeight),
                                     width: vImagePixelCount(chromaWidth), rowBytes: chromaWidth)
        var crBuffer = vImage_Buffer(data: cr, height: vImagePixelCount(chromaHeight),
                                     width: vImagePixelCount(chromaWidth), rowBytes: chromaWidth)
        let error = withUnsafeMutablePointer(to: &cbBuffer) { cbPointer in
            withUnsafeMutablePointer(to: &crBuffer) { crPointer in
                var sources: [UnsafeRawPointer?] = [UnsafeRawPointer(chroma), UnsafeRawPointer(chroma + 1)]
                var destinations: [UnsafePointer<vImage_Buffer>?] = [UnsafePointer(cbPointer), UnsafePointer(crPointer)]
                return vImageConvert_ChunkyToPlanar8(&sources, &destinations, 2, 2,
                                                     vImagePixelCount(chromaWidth), vImagePixelCount(chromaHeight),
                                                     chromaStride, vImage_Flags(kvImageNoFlags))
            }
        }
        guard error == kvImageNoError else {
            throw EncodingError.encoderFailure("chroma deinterleave failed (vImage error \(error))")
        }
    }
}

/// Bounded hand-off between the capture queue and the encoder thread.
/// Frames are recycled so steady-state recording allocates nothing.
final class I420FrameQueue: @unchecked Sendable {
    enum Item {
        case frame(I420Frame)
        case endOfStream
        case cancelled
    }

    private let condition = NSCondition()
    private let width: Int
    private let height: Int
    private let capacity: Int
    private var pending: [I420Frame] = []
    private var free: [I420Frame] = []
    private var endRequested = false
    private var cancelRequested = false
    private var dropCount = 0

    var droppedFrames: Int {
        condition.lock()
        defer { condition.unlock() }
        return dropCount
    }

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelRequested
    }

    init(width: Int, height: Int, capacity: Int) {
        self.width = width
        self.height = height
        self.capacity = max(capacity, 1)
    }

    /// Copies the frame and enqueues it, or drops it (returning false) when the encoder is behind.
    @discardableResult
    func enqueue(_ pixelBuffer: CVPixelBuffer, ptsMilliseconds: Int64) throws -> Bool {
        condition.lock()
        guard !endRequested, !cancelRequested else {
            condition.unlock()
            throw EncodingError.alreadyFinished
        }
        guard pending.count < capacity else {
            dropCount += 1
            condition.unlock()
            return false
        }
        let frame = free.popLast() ?? I420Frame(width: width, height: height)
        condition.unlock()

        // The copy happens outside the lock so the encoder thread is never stalled by it.
        do {
            try frame.copy(fromNV12: pixelBuffer)
        } catch {
            recycle(frame)
            throw error
        }
        frame.ptsMilliseconds = ptsMilliseconds

        condition.lock()
        pending.append(frame)
        condition.signal()
        condition.unlock()
        return true
    }

    /// Blocks the encoder thread until a frame, end of stream or cancellation is available.
    func next() -> Item {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if cancelRequested { return .cancelled }
            if !pending.isEmpty { return .frame(pending.removeFirst()) }
            if endRequested { return .endOfStream }
            condition.wait()
        }
    }

    func recycle(_ frame: I420Frame) {
        condition.lock()
        free.append(frame)
        condition.unlock()
    }

    func requestEndOfStream() {
        condition.lock()
        endRequested = true
        condition.signal()
        condition.unlock()
    }

    func requestCancel() {
        condition.lock()
        cancelRequested = true
        pending.removeAll()
        condition.signal()
        condition.unlock()
    }
}
