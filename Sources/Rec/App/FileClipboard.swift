import AppKit

/// Puts files on the general pasteboard so they paste into Finder, Slack, Messages, etc.
enum FileClipboard {
    enum ExportError: LocalizedError {
        case pasteboardRejected
        var errorDescription: String? { "The clipboard did not accept the file." }
    }

    static func copy(_ fileURL: URL) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([fileURL as NSURL]) else { throw ExportError.pasteboardRejected }
    }

    /// Places the H.264 companion next to the recording as `<basename>.mp4`, once.
    /// An existing file is reused so repeated clicks never duplicate it.
    static func exportCompanion(_ companion: URL, nextTo recording: URL) throws -> URL {
        let destination = recording.deletingPathExtension().appendingPathExtension("mp4")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }
        try FileManager.default.copyItem(at: companion, to: destination)
        return destination
    }
}
