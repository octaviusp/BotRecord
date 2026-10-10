import Foundation

extension OutputFormat {
    /// Toast wording: "WebM AV1", "MP4 H.264".
    var spokenLabel: String { label.replacingOccurrences(of: " · ", with: " ") }
}

extension String {
    /// Home folder shown as "~", like Terminal and Finder paths.
    var abbreviatedPath: String { (self as NSString).abbreviatingWithTildeInPath }
}
