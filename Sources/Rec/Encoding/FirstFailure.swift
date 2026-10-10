import Foundation

/// Remembers the first error raised on any of a sink's threads, so later calls can rethrow it.
final class FirstFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var error: Error?

    var current: Error? { lock.withLock { error } }

    func record(_ newError: Error) {
        lock.withLock { if error == nil { error = newError } }
    }

    func throwIfFailed() throws {
        if let current { throw current }
    }
}
