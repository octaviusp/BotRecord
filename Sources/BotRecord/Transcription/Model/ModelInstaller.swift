import CryptoKit
import Foundation

/// Puts a model's files on disk: downloads into a hidden staging folder (resumable across attempts and
/// launches), verifies every file's SHA-256, then renames the folder into place, so the installed folder
/// is either complete and verified or absent.
struct ModelInstaller: Sendable {
    let manifest: TranscriptionModelManifest
    let root: URL

    var installedFolder: URL { root.appendingPathComponent(manifest.folderName, isDirectory: true) }
    private var stagingFolder: URL { root.appendingPathComponent(".\(manifest.folderName).partial", isDirectory: true) }

    /// Cheap check for launch: every file present with its expected size (hashes were checked when installed).
    var isInstalled: Bool {
        manifest.files.allSatisfy { Self.fileSize(installedFolder.appendingPathComponent($0.name)) == $0.bytes }
    }

    /// Bytes an interrupted download already holds, so the next one shows where it resumes.
    var stagedBytes: Int64 {
        manifest.files.reduce(0) { total, file in
            total + min(file.bytes, Self.fileSize(stagingFolder.appendingPathComponent(file.name)))
        }
    }

    /// - Parameter onProgress: total bytes on disk so far, called on a background queue.
    func install(onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        var completedBytes: Int64 = 0
        for file in manifest.files {
            let base = completedBytes
            try await fetch(file) { onProgress(base + $0) }
            completedBytes += file.bytes
            onProgress(completedBytes)
        }
        if manager.fileExists(atPath: installedFolder.path) { try manager.removeItem(at: installedFolder) }
        try manager.moveItem(at: stagingFolder, to: installedFolder)
    }

    /// Deletes the installed model and any partial download.
    func remove() throws {
        let manager = FileManager.default
        for folder in [installedFolder, stagingFolder] where manager.fileExists(atPath: folder.path) {
            try manager.removeItem(at: folder)
        }
    }

    private func fetch(_ file: TranscriptionModelManifest.File, onProgress: @escaping @Sendable (Int64) -> Void) async throws {
        let destination = stagingFolder.appendingPathComponent(file.name)
        if Self.fileSize(destination) > file.bytes { try FileManager.default.removeItem(at: destination) }
        if Self.fileSize(destination) < file.bytes {
            try await RangedDownload.run(manifest.remoteURL(for: file), into: destination, onProgress: onProgress)
        }
        try Task.checkCancellation()
        let size = Self.fileSize(destination)
        guard size == file.bytes else {
            try FileManager.default.removeItem(at: destination)
            throw ModelDownloadError.sizeMismatch(file: file.name, expected: file.bytes, actual: size)
        }
        guard try Self.sha256(of: destination) == file.sha256 else {
            try FileManager.default.removeItem(at: destination)
            throw ModelDownloadError.checksumMismatch(file: file.name)
        }
    }

    /// Streams the file through SHA-256 in 8 MB reads (the weights are 730 MB).
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() } // read-only handle: closing can't lose data
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 8 << 20), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 0 when the file doesn't exist.
    static func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
