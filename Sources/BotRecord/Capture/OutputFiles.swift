import Foundation

enum OutputFiles {
    /// Deletes a discarded output. A missing file is fine; any other failure is logged so leftovers are traceable.
    static func removeIfPresent(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        } catch {
            captureLog.error("Could not delete \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
