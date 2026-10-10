import Foundation
import os

enum CompanionCache {
    static let maximumAge: TimeInterval = 24 * 60 * 60

    /// Companion MP4s exist only for "Copy as MP4"; anything older than a day is dead weight.
    static func purgeExpired(now: Date = Date()) {
        let logger = Logger(subsystem: AppPaths.identifier, category: "companions")
        let directory = AppPaths.companionsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, now.timeIntervalSince(modified) > maximumAge else { continue }
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                logger.error("Could not purge \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
}
