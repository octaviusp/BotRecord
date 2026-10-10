import Foundation

/// Failures raised by the AV1 sinks. Messages are user-presentable.
enum EncodingError: LocalizedError {
    case encoderSetup(String)
    case encoderFailure(String)
    case audioFormat(String)
    case fileWrite(URL, underlying: Error)
    case unsupported(String)
    case alreadyFinished

    var errorDescription: String? {
        switch self {
        case .encoderSetup(let detail):
            "Could not start the AV1 encoder: \(detail)"
        case .encoderFailure(let detail):
            "The AV1 encoder failed: \(detail)"
        case .audioFormat(let detail):
            "Unsupported audio format: \(detail)"
        case .fileWrite(let url, let underlying):
            "Could not write \(url.lastPathComponent) (is the disk full?): \(underlying.localizedDescription)"
        case .unsupported(let detail):
            detail
        case .alreadyFinished:
            "The recording file was already finalized or cancelled."
        }
    }
}
