import Foundation
import os

/// Whether summaries can run: Claude Code installed and signed in with at least one configured account.
enum ClaudeConnectionStatus: Equatable, Sendable {
    case notInstalled
    case signedOut
    /// `account` is the configured label ("default" or a config directory); `method` is Claude Code's
    /// `authMethod`, e.g. "claude.ai".
    case connected(account: String, method: String)
}

/// Seam for `ClaudeConnection`: the real one asks `claude auth status`.
protocol ClaudeAuthProbing: Sendable {
    func status() async -> ClaudeConnectionStatus
    /// Starts Claude Code's browser sign-in for the first configured account. Returns when the CLI exits
    /// (signed in, failed or timed out); cancelling the task stops it.
    func signIn(timeout: Duration) async throws
}

struct ClaudeCLIAuthProbe: ClaudeAuthProbing {
    var executable: ClaudeExecutable = .shared
    var accounts: @Sendable () -> [ClaudeAccount] = { ClaudeAccount.configured() }
    var runner: ProcessRunning = ProcessRunner()

    private static let statusTimeout: Duration = .seconds(5)
    private static let logger = Logger(subsystem: AppPaths.identifier, category: "claude")

    /// Connected when ANY configured account is signed in, matching the summarizer's fallback across accounts.
    func status() async -> ClaudeConnectionStatus {
        guard let claude = try? await executable.resolve() else { return .notInstalled }
        for account in accounts() where account.isConfigured {
            if let method = await signedInMethod(claude, account: account) {
                return .connected(account: account.label, method: method)
            }
        }
        return .signedOut
    }

    func signIn(timeout: Duration) async throws {
        let claude = try await executable.resolve()
        let account = accounts().first ?? .defaultLogin
        let output = try await runner.run(invocation(claude, ["auth", "login"], account: account), timeout: timeout)
        if output.exitCode != 0 {
            let stderr = String(decoding: output.standardError, as: UTF8.self)
            Self.logger.error("claude auth login exited \(output.exitCode): \(stderr, privacy: .public)")
        }
    }

    private struct AuthStatus: Decodable {
        let loggedIn: Bool
        let authMethod: String?
    }

    /// `claude auth status` prints JSON and exits 1 when signed out, so the JSON decides, not the exit code.
    private func signedInMethod(_ claude: URL, account: ClaudeAccount) async -> String? {
        do {
            let output = try await runner.run(invocation(claude, ["auth", "status"], account: account),
                                              timeout: Self.statusTimeout)
            let status = try JSONDecoder().decode(AuthStatus.self, from: output.standardOutput)
            return status.loggedIn ? status.authMethod ?? "claude" : nil
        } catch ProcessRunError.timedOut {
            Self.logger.error("claude auth status timed out for \(account.label, privacy: .public); treating it as signed out")
            return nil
        } catch {
            Self.logger.error("claude auth status unreadable for \(account.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func invocation(_ claude: URL, _ arguments: [String], account: ClaudeAccount) -> ProcessInvocation {
        ProcessInvocation(
            executable: claude,
            arguments: arguments,
            environment: account.environment(base: ProcessInfo.processInfo.environment),
            workingDirectory: FileManager.default.temporaryDirectory,
            standardInput: Data()
        )
    }
}
