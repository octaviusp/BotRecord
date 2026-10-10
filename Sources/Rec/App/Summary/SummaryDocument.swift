import Foundation

/// The parts of `summary.md` the library reuses: the title (folder name, meta.json) and the decisions (decisions.md).
struct SummaryDocument: Equatable {
    let title: String?
    let decisions: [String]

    private static let decisionHeadings: Set<String> = ["decisiones", "decisions"]
    /// What the prompt asks for when a section is empty; not a decision to log.
    private static let emptyMarkers: Set<String> = [
        "ninguno", "ninguna", "none", "ninguna decision registrada", "no decisions recorded", "sin decisiones",
    ]

    init(markdown: String) {
        var title: String?
        var decisions: [String] = []
        var inDecisions = false
        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if title == nil, line.hasPrefix("# ") {
                title = Self.plain(String(line.dropFirst(2)))
            } else if line.hasPrefix("## ") {
                inDecisions = Self.decisionHeadings.contains(Self.plain(String(line.dropFirst(3))).lowercased())
            } else if inDecisions, rawLine.hasPrefix("- ") || rawLine.hasPrefix("* ") {
                let bullet = String(rawLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !Self.isEmptyMarker(bullet) { decisions.append(bullet) }
            }
        }
        self.title = title.flatMap { $0.isEmpty ? nil : $0 }
        self.decisions = decisions
    }

    /// Strips Markdown emphasis and code marks so the title reads cleanly in meta.json and folder names.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "#*_")))
    }

    private static func isEmptyMarker(_ bullet: String) -> Bool {
        let folded = bullet
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return emptyMarkers.contains(folded)
    }
}
