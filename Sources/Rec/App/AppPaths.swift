import Foundation

/// Locations the app owns outside the user's output folder.
enum AppPaths {
    static let identifier = "local.tools.screen-recorder"

    static let cachesRoot = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(identifier, isDirectory: true)

    /// Per-recording metadata JSON and thumbnail PNG used by the Recent list.
    static let recentsDirectory = cachesRoot.appendingPathComponent("recents", isDirectory: true)

    /// Hardware H.264 copies recorded for "Copy as MP4"; purged after a day.
    static let companionsDirectory = cachesRoot.appendingPathComponent("companions", isDirectory: true)
}
