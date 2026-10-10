import CoreMedia
import Foundation

/// recording → finishing, or → cancelled from either. Guards the MediaSink call contract.
final class SinkLifecycle: @unchecked Sendable {
    private enum State { case recording, finishing, cancelled }

    private let lock = NSLock()
    private var state = State.recording

    func ensureRecording() throws {
        try lock.withLock {
            guard state == .recording else { throw EncodingError.alreadyFinished }
        }
    }

    func beginFinishing() throws {
        try lock.withLock {
            guard state == .recording else { throw EncodingError.alreadyFinished }
            state = .finishing
        }
    }

    /// Returns false when already cancelled, so teardown runs once.
    func cancel() -> Bool {
        lock.withLock {
            guard state != .cancelled else { return false }
            state = .cancelled
            return true
        }
    }
}

extension CMTime {
    /// Rounded milliseconds, the timestamp unit of both AV1 sinks.
    func milliseconds() throws -> Int64 {
        guard isNumeric else { throw EncodingError.encoderFailure("invalid presentation time \(self)") }
        return Int64((seconds * 1_000).rounded())
    }
}
