import Foundation

/// Locations the app owns outside the user's output folder.
enum AppPaths {
    static let identifier = "com.octaviusp.botrecord"

    static let cachesRoot = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(identifier, isDirectory: true)

    /// Per-recording metadata JSON and thumbnail PNG used by the Recent list.
    static let recentsDirectory = cachesRoot.appendingPathComponent("recents", isDirectory: true)

    /// Hardware H.264 copies recorded for "Copy as MP4"; purged after a day.
    static let companionsDirectory = cachesRoot.appendingPathComponent("companions", isDirectory: true)

    static let applicationSupportRoot = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(identifier, isDirectory: true)

    /// Downloaded speech models, one folder per model and revision. Not a cache: re-downloading costs 730 MB.
    static let modelsDirectory = applicationSupportRoot.appendingPathComponent("models", isDirectory: true)
}
