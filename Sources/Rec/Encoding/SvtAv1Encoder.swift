import CSvtAv1
import CoreVideo
import Foundation
import os

struct EncodedVideoPacket {
    /// Temporal unit without temporal delimiter OBUs.
    let data: Data
    let ptsMilliseconds: Int64
    let isKeyframe: Bool
}

/// SVT-AV1 wrapper. Frames are copied on the caller's queue and encoded on a dedicated
/// thread, so `encode` never blocks capture on the encoder.
final class SvtAv1Encoder: @unchecked Sendable {
    /// `av1C` record (4-byte header + sequence header OBU).
    let codecConfiguration: Data
    var droppedFrames: Int { frames.droppedFrames }

    private let frames: I420FrameQueue
    private let finished = DispatchGroup()
    private var handle: UnsafeMutablePointer<EbComponentType>?
    /// Set when the send thread had to call `svt_av1_enc_deinit` early to unblock the receiver.
    private var queuesShutDown = false
    /// Only touched from the capture queue.
    private var lastPtsMilliseconds: Int64 = -1

    init(config: VideoEncodeConfig) throws {
        // Half a second of backlog: more than that means the encoder can't keep up, so drop.
        frames = I420FrameQueue(width: config.width, height: config.height, capacity: max(config.frameRate / 2, 1))
        SvtLogRouter.install()

        var parameters = EbSvtAv1EncConfiguration()
        var newHandle: UnsafeMutablePointer<EbComponentType>?
        try Self.check(svt_av1_enc_init_handle(&newHandle, &parameters), "init_handle")
        guard let newHandle else { throw EncodingError.encoderSetup("SVT-AV1 returned no handle") }
        do {
            Self.apply(config, to: &parameters)
            try Self.check(svt_av1_enc_set_parameter(newHandle, &parameters), "set_parameter")
            try Self.check(svt_av1_enc_init(newHandle), "init")
            codecConfiguration = try Self.readCodecConfiguration(newHandle)
        } catch {
            // deinit tolerates a handle whose init failed, mirroring ffmpeg's teardown.
            svt_av1_enc_deinit(newHandle)
            svt_av1_enc_deinit_handle(newHandle)
            throw error
        }
        handle = newHandle
    }

    /// Covers the case where the owner failed before calling `start`; otherwise the thread already released SVT.
    deinit {
        releaseEncoder()
    }

    /// Launches the sender and receiver threads. Call once, before the first `encode`.
    /// They are separate because `send_picture` blocks while SVT's output pool is full:
    /// draining packets on the sending thread deadlocks under load.
    /// - Parameters:
    ///   - onPacket: called on the receiver thread, in decode order (= presentation order for AV1 temporal units).
    ///   - onError: called once, on either thread, when encoding fails; later packets are discarded.
    func start(onPacket: @escaping (EncodedVideoPacket) throws -> Void, onError: @escaping (Error) -> Void) {
        finished.enter()
        let threads = DispatchGroup()
        spawnThread("rec.svt-av1.send", in: threads) { [self] in runSendLoop(onError: onError) }
        spawnThread("rec.svt-av1.receive", in: threads) { [self] in runReceiveLoop(onPacket: onPacket, onError: onError) }
        threads.notify(queue: .global(qos: .userInitiated)) { [self] in
            releaseEncoder()
            finished.leave()
        }
    }

    /// Copies the frame and queues it. Returns false when it was dropped for backpressure.
    @discardableResult
    func encode(_ pixelBuffer: CVPixelBuffer, ptsMilliseconds: Int64) throws -> Bool {
        // SVT needs strictly increasing pts; sub-millisecond neighbours get nudged forward.
        let pts = max(ptsMilliseconds, lastPtsMilliseconds + 1)
        let accepted = try frames.enqueue(pixelBuffer, ptsMilliseconds: pts)
        if accepted { lastPtsMilliseconds = pts }
        return accepted
    }

    /// Sends end-of-stream and waits until every packet has been delivered.
    func finish() async {
        frames.requestEndOfStream()
        await withCheckedContinuation { continuation in
            finished.notify(queue: .global(qos: .userInitiated)) { continuation.resume() }
        }
    }

    /// Stops feeding frames and discards remaining packets; `whenStopped` runs once SVT is released.
    func cancel(whenStopped: @escaping () -> Void, on queue: DispatchQueue) {
        frames.requestCancel()
        finished.notify(queue: queue, execute: whenStopped)
    }

    // MARK: - Encoder threads

    private func spawnThread(_ name: String, in group: DispatchGroup, _ body: @escaping () -> Void) {
        group.enter()
        let thread = Thread {
            body()
            group.leave()
        }
        thread.name = name
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Runs after both threads ended, so nothing else touches the handle.
    private func releaseEncoder() {
        guard let handle else { return }
        if !queuesShutDown { svt_av1_enc_deinit(handle) }
        svt_av1_enc_deinit_handle(handle)
        self.handle = nil
    }

    private func runSendLoop(onError: (Error) -> Void) {
        guard let handle else { return }
        do {
            sending: while true {
                switch frames.next() {
                case .frame(let frame):
                    defer { frames.recycle(frame) }
                    try send(frame, to: handle)
                case .endOfStream, .cancelled:
                    break sending
                }
            }
        } catch {
            frames.requestCancel()
            onError(error)
        }
        // EOS goes out on every path: it is what lets the receiver thread finish.
        do {
            try sendEndOfStream(to: handle)
        } catch {
            frames.requestCancel()
            onError(error)
            // Without EOS the receiver would block forever; deinit shuts SVT's queues to release it.
            svt_av1_enc_deinit(handle)
            queuesShutDown = true
        }
    }

    private func runReceiveLoop(onPacket: (EncodedVideoPacket) throws -> Void, onError: (Error) -> Void) {
        guard let handle else { return }
        var failed = false
        func fail(_ error: Error) {
            guard !failed else { return }
            failed = true
            frames.requestCancel()
            onError(error)
        }
        while true {
            var output: UnsafeMutablePointer<EbBufferHeaderType>?
            // pic_send_done = 1 makes get_packet block until a packet exists, so this thread never spins.
            let status = svt_av1_enc_get_packet(handle, &output, 1)
            if status == EB_NoErrorFifoShutdown { return }
            guard let packetHeader = output else {
                if status == EB_NoErrorEmptyQueue { continue }
                fail(EncodingError.encoderFailure("svt_av1_enc_get_packet returned \(Self.describe(status)) without a packet"))
                return
            }
            defer { svt_av1_enc_release_out_buffer(&output) }
            let header = packetHeader.pointee
            if status != EB_ErrorNone || header.flags & UInt32(EB_BUFFERFLAG_ERROR_MASK) != 0 {
                fail(EncodingError.encoderFailure("encoder reported an error (\(Self.describe(status)), flags \(header.flags))"))
            } else if !failed, !frames.isCancelled, header.n_filled_len > 0, let bytes = header.p_buffer {
                do {
                    let raw = Data(bytes: bytes, count: Int(header.n_filled_len))
                    try onPacket(EncodedVideoPacket(data: try AV1Bitstream.strippingTemporalDelimiters(raw),
                                                    ptsMilliseconds: header.pts,
                                                    isKeyframe: header.pic_type == EB_AV1_KEY_PICTURE))
                } catch {
                    fail(error)
                }
            }
            if header.flags & UInt32(EB_BUFFERFLAG_EOS) != 0 { return }
        }
    }

    private func send(_ frame: I420Frame, to handle: UnsafeMutablePointer<EbComponentType>) throws {
        var picture = EbSvtIOFormat(luma: frame.luma, cb: frame.cb, cr: frame.cr,
                                    y_stride: UInt32(frame.width),
                                    cr_stride: UInt32(frame.chromaWidth),
                                    cb_stride: UInt32(frame.chromaWidth))
        let byteCount = UInt32(frame.width * frame.height * 3 / 2)
        // SVT copies the planes inside send_picture, so the frame can be recycled right after.
        try withUnsafeMutablePointer(to: &picture) { picturePointer in
            var header = EbBufferHeaderType()
            header.size = UInt32(MemoryLayout<EbBufferHeaderType>.size)
            header.p_buffer = UnsafeMutableRawPointer(picturePointer).assumingMemoryBound(to: UInt8.self)
            header.n_filled_len = byteCount
            header.n_alloc_len = byteCount
            header.pts = frame.ptsMilliseconds
            header.pic_type = EB_AV1_INVALID_PICTURE // let the encoder choose the frame type
            try Self.check(svt_av1_enc_send_picture(handle, &header), "send_picture")
        }
    }

    private func sendEndOfStream(to handle: UnsafeMutablePointer<EbComponentType>) throws {
        var header = EbBufferHeaderType()
        header.size = UInt32(MemoryLayout<EbBufferHeaderType>.size)
        header.flags = UInt32(EB_BUFFERFLAG_EOS)
        header.pic_type = EB_AV1_INVALID_PICTURE
        try Self.check(svt_av1_enc_send_picture(handle, &header), "send_picture(EOS)")
    }

    // MARK: - Setup helpers

    private static func apply(_ config: VideoEncodeConfig, to parameters: inout EbSvtAv1EncConfiguration) {
        switch config.compression {
        case .fastest:
            // 12 measured 3.2x larger than 10 for no speed gain on screen content; 11 is the useful ceiling.
            parameters.enc_mode = 11
        case .balanced:
            parameters.enc_mode = 10
        case .smallest:
            // Screen-content tools only run at presets <= 8; they pay off on UI text.
            parameters.enc_mode = 8
            parameters.screen_content_mode = 1
        }
        parameters.source_width = UInt32(config.width)
        parameters.source_height = UInt32(config.height)
        parameters.frame_rate_numerator = UInt32(config.frameRate)
        parameters.frame_rate_denominator = 1
        parameters.encoder_bit_depth = 8
        parameters.encoder_color_format = EB_YUV420
        parameters.rate_control_mode = UInt8(SVT_AV1_RC_MODE_CQP_OR_CRF.rawValue)
        parameters.qp = 36 // CRF value (aq_mode stays at its default, which selects CRF over CQP)
        // Closed GOP so every keyframe is a clean seek point for browsers.
        parameters.intra_refresh_type = SVT_AV1_KF_REFRESH
        parameters.intra_period_length = Int32(config.frameRate * 10 - 1)
        parameters.color_primaries = EB_CICP_CP_BT_709
        parameters.transfer_characteristics = EB_CICP_TC_BT_709
        parameters.matrix_coefficients = EB_CICP_MC_BT_709
        parameters.color_range = EB_CR_STUDIO_RANGE
    }

    private static func readCodecConfiguration(_ handle: UnsafeMutablePointer<EbComponentType>) throws -> Data {
        var headerBuffer: UnsafeMutablePointer<EbBufferHeaderType>?
        try check(svt_av1_enc_stream_header(handle, &headerBuffer), "stream_header")
        guard let headerBuffer else { throw EncodingError.encoderSetup("SVT-AV1 returned no stream header") }
        defer { svt_av1_enc_stream_header_release(headerBuffer) }
        guard let bytes = headerBuffer.pointee.p_buffer else {
            throw EncodingError.encoderSetup("SVT-AV1 stream header is empty")
        }
        let header = Data(bytes: bytes, count: Int(headerBuffer.pointee.n_filled_len))
        return try AV1Bitstream.codecConfigurationRecord(fromStreamHeader: header)
    }

    private static func check(_ status: EbErrorType, _ call: String) throws {
        guard status == EB_ErrorNone else {
            throw EncodingError.encoderFailure("svt_av1_enc_\(call) returned \(describe(status))")
        }
    }

    private static func describe(_ status: EbErrorType) -> String {
        "0x" + String(UInt32(bitPattern: status.rawValue), radix: 16)
    }
}

/// Routes SVT-AV1's stderr chatter to the unified log, keeping only warnings and errors.
private enum SvtLogRouter {
    private static let logger = Logger(subsystem: "local.tools.rec", category: "svt-av1")
    private static let installOnce: Void = {
        svt_av1_set_log_callback({ _, level, _, format, arguments in
            guard let format, let arguments, level.rawValue <= SVT_AV1_LOG_WARN.rawValue else { return }
            var buffer = [CChar](repeating: 0, count: 512)
            _ = vsnprintf(&buffer, buffer.count, format, arguments)
            let message = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
            SvtLogRouter.logger.warning("\(message, privacy: .public)")
        }, nil)
    }()

    static func install() { _ = installOnce }
}
