import Foundation

/// A Claude Code login, selected through `CLAUDE_CONFIG_DIR` the same way the user's `cl`/`cl2` aliases do.
struct ClaudeAccount: Equatable, Sendable {
    /// Recorded in meta.json and shown in errors.
    let label: String
    /// Nil means Claude Code's default (`~/.claude`), so the variable is removed rather than set.
    let configDirectory: URL?

    /// Personal account first (`cl2`), then work (`cl`): summaries spend personal quota before work quota.
    static func fallbackOrder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ClaudeAccount] {
        [
            ClaudeAccount(label: "personal", configDirectory: home.appendingPathComponent(".claude-personal", isDirectory: true)),
            ClaudeAccount(label: "work", configDirectory: nil),
        ]
    }

    /// A configured directory that doesn't exist has no login; skipping it avoids a slow failing launch.
    var isConfigured: Bool {
        guard let configDirectory else { return true }
        return FileManager.default.fileExists(atPath: configDirectory.path)
    }

    func environment(base: [String: String]) -> [String: String] {
        var environment = base
        environment["CLAUDE_CONFIG_DIR"] = configDirectory?.path
        return environment
    }
}

/// Finds the `claude` binary: GUI apps get a minimal PATH, so the user's install location is the fallback.
enum ClaudeExecutable {
    static func resolve(
        path: String? = ProcessInfo.processInfo.environment["PATH"],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> URL {
        let manager = FileManager.default
        let fromPath = (path ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("claude") }
        let fallback = home.appendingPathComponent(".local/bin/claude")
        guard let found = (fromPath + [fallback]).first(where: { manager.isExecutableFile(atPath: $0.path) }) else {
            throw SummaryError.claudeNotInstalled
        }
        return found
    }
}
