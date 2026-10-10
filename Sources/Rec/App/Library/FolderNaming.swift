import Foundation

/// Meeting folder names: `<YYYY-MM-DD-HHmm>-<title>`, kebab-case ASCII, at most 60 characters,
/// so they sort by date, survive any filesystem or shell, and read well in a path.
enum FolderNaming {
    static let maxLength = 60
    /// Placeholder title until the summary names the meeting.
    static let untitled = "meeting"

    static func initialName(startedAt: Date) -> String {
        titledName(startedAt: startedAt, title: untitled)
    }

    static func titledName(startedAt: Date, title: String) -> String {
        let prefix = datePrefix(startedAt)
        let titleSlug = slug(title, maxLength: max(0, maxLength - prefix.count - 1))
        return String(([prefix, titleSlug.isEmpty ? untitled : titleSlug]).joined(separator: "-").prefix(maxLength))
    }

    /// "Revisión de Pricing Q4!" → "revision-de-pricing-q4". Cuts at a word boundary when too long,
    /// dropping dangling connectors so a cut title doesn't end in "-de" or "-the".
    static func slug(_ text: String, maxLength: Int) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        var pendingHyphen = false
        for scalar in folded.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingHyphen, !slug.isEmpty { slug.append("-") }
                slug.unicodeScalars.append(scalar)
                pendingHyphen = false
            } else {
                pendingHyphen = true
            }
        }
        guard slug.count > maxLength else { return slug }
        var words = slug.prefix(maxLength).split(separator: "-")
        let cutMidWord = slug[slug.index(slug.startIndex, offsetBy: maxLength)] != "-"
        if cutMidWord, words.count > 1 { words.removeLast() }
        while words.count > 1, let last = words.last, connectors.contains(String(last)) { words.removeLast() }
        return words.joined(separator: "-")
    }

    private static let connectors: Set<String> = [
        "a", "al", "con", "de", "del", "el", "en", "la", "las", "los", "para", "por", "y",
        "and", "for", "in", "of", "on", "the", "to", "with",
    ]

    static func datePrefix(_ date: Date) -> String {
        prefixFormatter.string(from: date)
    }

    private static let prefixFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}
