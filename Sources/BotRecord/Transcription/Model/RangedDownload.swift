import Foundation

enum ModelDownloadError: LocalizedError {
    case httpStatus(Int, file: String)
    case sizeMismatch(file: String, expected: Int64, actual: Int64)
    case checksumMismatch(file: String)

    var errorDescription: String? {
        switch self {
        case let .httpStatus(status, file): "Download of \(file) failed (HTTP \(status))."
        case let .sizeMismatch(file, expected, actual): "\(file) has \(actual) bytes, expected \(expected)."
        case let .checksumMismatch(file): "\(file) is corrupted (checksum mismatch); it was deleted, try again."
        }
    }
}

/// Downloads one URL into a file, continuing from whatever an earlier attempt left there (HTTP Range),
/// so a cancelled download, a lost connection or a quit app resumes instead of starting over.
/// Bytes stream straight to disk; memory stays flat for any file size.
final class RangedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Called on a background queue with the file's size so far.
    typealias Progress = @Sendable (Int64) -> Void

    private let destination: URL
    private let fileName: String
    private let onProgress: Progress
    // Delegate callbacks arrive serially on `delegateQueue`, the only place the state below is touched.
    private let delegateQueue: OperationQueue
    private var handle: FileHandle?
    private var written: Int64
    private var failure: Error?
    private var continuation: CheckedContinuation<Void, Error>?

    private init(destination: URL, onProgress: @escaping Progress) {
        self.destination = destination
        fileName = destination.lastPathComponent
        self.onProgress = onProgress
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        written = ModelInstaller.fileSize(destination)
    }

    /// Appends the missing bytes of `url` to `destination`. Cancelling the task stops the transfer and keeps the partial file.
    static func run(_ url: URL, into destination: URL, onProgress: @escaping Progress) async throws {
        let download = RangedDownload(destination: destination, onProgress: onProgress)
        try await download.start(url)
    }

    private func start(_ url: URL) async throws {
        var request = URLRequest(url: url)
        if written > 0 { request.setValue("bytes=\(written)-", forHTTPHeaderField: "Range") }
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: delegateQueue)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegateQueue.addOperation {
                    self.continuation = continuation
                    task.resume()
                }
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            switch status {
            case 206:
                try openDestination(truncating: false)
            case 200:
                // The server ignored the range: start the file over.
                try openDestination(truncating: true)
            default:
                throw ModelDownloadError.httpStatus(status, file: fileName)
            }
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, let handle else { return }
        do {
            try handle.write(contentsOf: data)
            written += Int64(data.count)
            onProgress(written)
        } catch {
            failure = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let closeError: Error?
        do {
            try handle?.close()
            closeError = nil
        } catch {
            closeError = error
        }
        handle = nil
        let outcome = failure ?? error ?? closeError
        if let outcome {
            continuation?.resume(throwing: outcome)
        } else {
            continuation?.resume()
        }
        continuation = nil
    }

    private func openDestination(truncating: Bool) throws {
        let manager = FileManager.default
        if truncating || !manager.fileExists(atPath: destination.path) {
            guard manager.createFile(atPath: destination.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination.path])
            }
            written = 0
        }
        let handle = try FileHandle(forWritingTo: destination)
        try handle.seekToEnd()
        self.handle = handle
    }
}
