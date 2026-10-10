import Foundation

/// Summarizes with a headless Claude Code run that has no tools at all: transcript in, Markdown out.
/// Tries each account in order, moving on only when the account itself is unavailable (quota, rate limit, login).
struct ClaudeCodeSummarizer: MeetingSummarizing {
    var model = "claude-haiku-5-5"
    var effort = "medium"
    var accounts: @Sendable () -> [ClaudeAccount] = { ClaudeAccount.configured() }
    var timeout: Duration = .seconds(300)
    var runner: ProcessRunning = ProcessRunner()
    var resolveExecutable: @Sendable () async throws -> URL = { try await ClaudeExecutable.shared.resolve() }

    func summarize(_ request: SummaryRequest) async throws -> MeetingSummary {
        let executable = try await resolveExecutable()
        let input = Data(SummaryPrompt.user(request).utf8)
        let deadline = ContinuousClock.now + timeout
        var problems: [String: AccountProblem] = [:]

        for account in accounts() {
            guard account.isConfigured else {
                problems[account.label] = .notLoggedIn
                continue
            }
            try Task.checkCancellation()
            let output: ProcessOutput
            do {
                output = try await runner.run(invocation(executable, account: account, input: input), timeout: deadline - .now)
            } catch ProcessRunError.timedOut {
                throw SummaryError.timedOut(minutes: Int(timeout.components.seconds / 60))
            }
            switch ClaudeResultInterpreter.interpret(output) {
            case let .success(markdown):
                let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { throw SummaryError.emptySummary }
                return MeetingSummary(markdown: trimmed + "\n", model: model, account: account.label)
            case let .accountUnavailable(problem):
                problems[account.label] = problem
            case let .failed(message):
                throw SummaryError.claudeFailed(message)
            }
        }
        throw SummaryError.noAccountAvailable(problems)
    }

    /// `--tools ""` removes every built-in tool, `--strict-mcp-config` every MCP server and `--safe-mode`
    /// hooks, plugins and CLAUDE.md: the run can only read the prompt and write text.
    private func invocation(_ executable: URL, account: ClaudeAccount, input: Data) -> ProcessInvocation {
        ProcessInvocation(
            executable: executable,
            arguments: [
                "-p",
                "--model", model,
                "--effort", effort,
                "--output-format", "json",
                "--tools", "",
                "--strict-mcp-config",
                "--safe-mode",
                "--no-session-persistence",
                "--system-prompt", SummaryPrompt.system,
            ],
            environment: account.environment(base: ProcessInfo.processInfo.environment),
            workingDirectory: FileManager.default.temporaryDirectory,
            standardInput: input
        )
    }
}
