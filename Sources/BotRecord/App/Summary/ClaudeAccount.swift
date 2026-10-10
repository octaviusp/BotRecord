import Foundation

/// A Claude Code login, selected through `CLAUDE_CONFIG_DIR` (Claude Code keeps one login per config directory).
struct ClaudeAccount: Equatable, Sendable {
    /// Recorded in meta.json and shown in errors.
    let label: String
    /// Nil means Claude Code's default (`~/.claude`), so the variable is removed rather than set.
    let configDirectory: URL?

    static let defaultLogin = ClaudeAccount(label: "default", configDirectory: nil)

    /// UserDefaults key: ordered array of config directory paths (`~` allowed). Summaries try them in order,
    /// moving to the next one when an account is out of quota or logged out. Empty or absent → the default login.
    static let configDirectoriesKey = "claudeConfigDirectories"

    /// Read on every use so a `defaults write` applies without relaunching.
    static func configured(
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [ClaudeAccount] {
        let paths = (defaults.stringArray(forKey: configDirectoriesKey) ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !paths.isEmpty else { return [defaultLogin] }
        return paths.map { path in
            let expanded = path == "~" || path.hasPrefix("~/")
                ? home.path + path.dropFirst()
                : path
            return ClaudeAccount(label: path, configDirectory: URL(fileURLWithPath: expanded, isDirectory: true))
        }
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
