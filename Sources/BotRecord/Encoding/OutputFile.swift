import Foundation
import os

/// Sequential file writer that can patch earlier bytes. Every failure (e.g. disk full)
/// surfaces as `EncodingError.fileWrite`.
final class OutputFile {
    let url: URL
    private let handle: FileHandle
    /// Current end of the written data.
    private(set) var offset: UInt64 = 0

    init(url: URL) throws {
        self.url = url
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw EncodingError.fileWrite(url, underlying: CocoaError(.fileWriteUnknown))
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw EncodingError.fileWrite(url, underlying: error)
        }
    }

    func write(_ data: Data) throws {
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw EncodingError.fileWrite(url, underlying: error)
        }
        offset += UInt64(data.count)
    }

    /// Overwrites bytes already written, then returns to the end of the file.
    func write(_ data: Data, at position: UInt64) throws {
        precondition(position + UInt64(data.count) <= offset, "patch must stay inside written data")
        do {
            try handle.seek(toOffset: position)
            try handle.write(contentsOf: data)
            try handle.seek(toOffset: offset)
        } catch {
            throw EncodingError.fileWrite(url, underlying: error)
        }
    }

    func close() throws {
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            throw EncodingError.fileWrite(url, underlying: error)
        }
    }

    /// Closes (best effort) and deletes the file; used when a recording is cancelled.
    func discard() {
        try? handle.close() // throws only when already closed, which is fine here
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger(subsystem: AppPaths.identifier, category: "encoding")
                .error("Could not delete cancelled recording \(self.url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
