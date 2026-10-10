import Foundation
import os

/// Finds the `claude` binary. Apps launched from Finder or launchd get a minimal PATH, so the user's login-shell
/// PATH is asked first, then the places Claude Code's installers use.
final class ClaudeExecutable: Sendable {
    static let shared = ClaudeExecutable()

    /// A found binary stays valid for the app's lifetime; a miss is retried so installing Claude Code later works.
    private let cache = OSAllocatedUnfairLock<URL?>(initialState: nil)
    private let runner: ProcessRunning
    private let home: URL

    init(runner: ProcessRunning = ProcessRunner(), home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.runner = runner
        self.home = home
    }

    /// Throws `SummaryError.claudeNotInstalled` when no executable `claude` exists anywhere it looks.
    func resolve() async throws -> URL {
        if let cached = cache.withLock({ $0 }), Self.isExecutable(cached) { return cached }
        let candidates = await [loginShellLocation()].compactMap { $0 } + fallbackLocations
        guard let found = candidates.first(where: Self.isExecutable) else {
            throw SummaryError.claudeNotInstalled
        }
        cache.withLock { $0 = found }
        return found
    }

    private var fallbackLocations: [URL] {
        [
            home.appendingPathComponent(".local/bin/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
        ]
    }

    /// `zsh -lc` reads the user's login profile (where installers add PATH entries). Bounded: a profile that
    /// waits for input must not hang the summary.
    private func loginShellLocation() async -> URL? {
        let invocation = ProcessInvocation(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: ["-lc", "command -v claude"],
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: home,
            standardInput: Data()
        )
        guard let output = try? await runner.run(invocation, timeout: .seconds(5)), output.exitCode == 0 else { return nil }
        // Profiles may print banners; the answer is the last absolute path printed.
        let path = String(decoding: output.standardOutput, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
        return path.map { URL(fileURLWithPath: $0) }
    }

    private static func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}
