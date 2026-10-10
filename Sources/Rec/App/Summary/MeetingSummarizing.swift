import Foundation

/// What a summarizer needs to know about one meeting.
struct SummaryRequest: Sendable {
    /// Contents of `transcript.md`.
    let transcript: String
    let startedAt: Date?
    let duration: TimeInterval?
}

struct MeetingSummary: Sendable {
    /// The full `summary.md`.
    let markdown: String
    let model: String
    /// Which account answered, e.g. "personal".
    let account: String
}

/// Strategy for turning a transcript into `summary.md`; Claude Code today, a local model later.
protocol MeetingSummarizing: Sendable {
    /// Throws `SummaryError`, or `CancellationError` when the calling task is cancelled.
    func summarize(_ request: SummaryRequest) async throws -> MeetingSummary
}

/// Why a summary failed, worded for the person pressing the button (the summary UI is Spanish).
enum SummaryError: LocalizedError, Equatable {
    case missingTranscript
    case claudeNotInstalled
    case timedOut(minutes: Int)
    /// Every account was out of tokens, rate limited or logged out; one reason per account label.
    case noAccountAvailable([String: AccountProblem])
    case claudeFailed(String)
    case emptySummary

    var errorDescription: String? {
        switch self {
        case .missingTranscript:
            "Esta reunión todavía no tiene transcript.md."
        case .claudeNotInstalled:
            "No encontré Claude Code: instalalo o revisá ~/.local/bin/claude."
        case let .timedOut(minutes):
            "Claude tardó más de \(minutes) min. Probá de nuevo."
        case let .noAccountAvailable(problems):
            Self.describe(problems)
        case let .claudeFailed(message):
            "Claude falló: \(message)"
        case .emptySummary:
            "Claude devolvió un resumen vacío. Probá de nuevo."
        }
    }

    private static func describe(_ problems: [String: AccountProblem]) -> String {
        if !problems.isEmpty, problems.values.allSatisfy({ $0 == .outOfTokens || $0 == .rateLimited }) {
            return problems.count > 1 ? "Sin tokens en ambas cuentas de Claude" : "Sin tokens en la cuenta de Claude"
        }
        let details = problems.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.spanishLabel)" }
        return "Ninguna cuenta de Claude disponible (\(details.joined(separator: " · ")))"
    }
}

/// Failures that mean "try the other account", not "the request is broken".
enum AccountProblem: String, Equatable, Sendable {
    case outOfTokens
    case rateLimited
    case notLoggedIn

    var spanishLabel: String {
        switch self {
        case .outOfTokens: "sin tokens"
        case .rateLimited: "límite de uso"
        case .notLoggedIn: "sin sesión, corré claude y /login"
        }
    }
}
