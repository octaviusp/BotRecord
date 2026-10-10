import Foundation

/// What one headless `claude -p --output-format json` run means for the summarizer.
enum ClaudeRunVerdict: Equatable {
    case success(String)
    /// Quota, rate limit or login: worth retrying with the next account.
    case accountUnavailable(AccountProblem)
    /// Anything else: retrying with another account would fail the same way.
    case failed(String)
}

/// Reads the JSON result of a headless run. Newer Claude Code prints an array of events whose last
/// `"type": "result"` entry carries `is_error`, `subtype`, `api_error_status` and `result`; older ones print that object alone.
enum ClaudeResultInterpreter {
    static func interpret(_ output: ProcessOutput) -> ClaudeRunVerdict {
        let result = resultEvent(in: output.standardOutput)
        let stderr = String(decoding: output.standardError, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        if let result, result.isError == false, output.exitCode == 0 {
            return .success(result.text ?? "")
        }
        if let problem = accountProblem(status: result?.apiErrorStatus, texts: [result?.text, result?.subtype, stderr]) {
            return .accountUnavailable(problem)
        }
        let message = [result?.text, stderr].compactMap { $0 }.first { !$0.isEmpty }
            ?? "salió con código \(output.exitCode) sin explicación"
        return .failed(String(message.prefix(300)))
    }

    private struct ResultEvent {
        let isError: Bool
        let subtype: String?
        let text: String?
        let apiErrorStatus: Int?
    }

    private static func resultEvent(in data: Data) -> ResultEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let events = (json as? [[String: Any]]) ?? [(json as? [String: Any])].compactMap { $0 }
        guard let event = events.last(where: { $0["type"] as? String == "result" }) else { return nil }
        return ResultEvent(
            isError: event["is_error"] as? Bool ?? true,
            subtype: event["subtype"] as? String,
            text: event["result"] as? String,
            apiErrorStatus: event["api_error_status"] as? Int
        )
    }

    private static func accountProblem(status: Int?, texts: [String?]) -> AccountProblem? {
        switch status {
        case 401, 403: return .notLoggedIn
        case 429: return .rateLimited
        default: break
        }
        let haystack = texts.compactMap { $0?.lowercased() }.joined(separator: "\n")
        if quotaPhrases.contains(where: haystack.contains) { return .outOfTokens }
        if ratePhrases.contains(where: haystack.contains) { return .rateLimited }
        if loginPhrases.contains(where: haystack.contains) { return .notLoggedIn }
        return nil
    }

    // Phrases Claude Code prints for subscription limits ("Claude AI usage limit reached", "You've hit your limit"),
    // API credit exhaustion ("Credit balance is too low") and logins ("Not logged in · Please run /login").
    private static let quotaPhrases = [
        "usage limit", "hit your limit", "limit reached", "credit balance", "out of credits", "quota",
        "out of extra usage", "spending cap", "weekly limit", "insufficient",
    ]
    private static let ratePhrases = ["rate limit", "rate_limit", "too many requests"]
    private static let loginPhrases = [
        "not logged in", "/login", "invalid api key", "authentication", "unauthorized", "oauth token",
        "token has expired", "token expired", "invalid bearer", "permission_error",
    ]
}
