import Foundation

enum OutputNaming {
    private static func timestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }

    /// `<directory>/<yyyy-MM-dd-HH-mm-ss>.<ext>`, suffixed `-2`, `-3`... when the name is taken.
    /// Creates the directory when missing.
    static func mainOutputURL(directory: URL, format: OutputFormat, date: Date = Date()) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = timestampFormatter().string(from: date)
        var candidate = directory.appendingPathComponent("\(baseName).\(format.fileExtension)")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(format.fileExtension)")
            suffix += 1
        }
        return candidate
    }

    /// Cache location of the hardware H.264 copy that backs "Copy as MP4". Any stale file with the
    /// same name is removed because `AVAssetWriter` refuses to overwrite.
    static func companionURL(forMainOutput mainURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let directory = AppPaths.companionsDirectory
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let baseName = mainURL.deletingPathExtension().lastPathComponent
        let url = directory.appendingPathComponent("\(baseName).mp4")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        return url
    }
}
