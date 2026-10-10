import AppKit
import Observation
import os

/// Whether summaries are available, as the popover and Settings show it, plus the "Connect Claude" action.
/// Checks run off the main thread, are cached for 30 s and never run while a capture is in progress.
@MainActor @Observable
final class ClaudeConnection {
    enum State: Equatable {
        case checking
        case notInstalled
        case signedOut
        /// Browser sign-in started from the app; polled until it completes.
        case connecting
        case connected(account: String, method: String)
    }

    static let installURL = URL(string: "https://claude.com/claude-code")!

    private(set) var state: State = .checking
    /// One line explaining what to do next, shown under the control; nil when there is nothing to say.
    private(set) var hint: String?

    @ObservationIgnored private let probe: ClaudeAuthProbing
    @ObservationIgnored private let isCapturing: @MainActor () -> Bool
    @ObservationIgnored private var checkedAt: ContinuousClock.Instant?
    @ObservationIgnored private var checkTask: Task<Void, Never>?
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    private static let freshness: Duration = .seconds(30)
    private static let signInTimeout: Duration = .seconds(180)
    private static let pollInterval: Duration = .seconds(2)

    init(probe: ClaudeAuthProbing = ClaudeCLIAuthProbe(), isCapturing: @escaping @MainActor () -> Bool) {
        self.probe = probe
        self.isCapturing = isCapturing
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    /// Popover and Settings call this when they appear; a result younger than 30 s is reused.
    func refreshIfStale() {
        if let checkedAt, ContinuousClock.now - checkedAt < Self.freshness { return }
        refresh()
    }

    /// Settings' "Re-check": always asks again.
    func refresh() {
        guard checkTask == nil, connectTask == nil, !isCapturing() else { return }
        if !isConnected { state = .checking }
        checkTask = Task {
            apply(await probe.status())
            checkTask = nil
        }
    }

    func connect() {
        switch state {
        case .notInstalled:
            NSWorkspace.shared.open(Self.installURL)
            hint = "Instalá Claude Code y volvé"
            // The next popover opening finds the fresh install.
            checkedAt = nil
        case .signedOut:
            startSignIn()
        case .checking, .connecting, .connected:
            return
        }
    }

    private func startSignIn() {
        state = .connecting
        hint = "Terminá de iniciar sesión en el navegador"
        let probe = probe
        let timeout = Self.signInTimeout
        connectTask = Task {
            let loginExited = OSAllocatedUnfairLock(initialState: false)
            let login = Task.detached {
                // Failures are logged by the probe; the status poll below decides what the user sees.
                try? await probe.signIn(timeout: timeout)
                loginExited.withLock { $0 = true }
            }
            defer { login.cancel() }
            let deadline = ContinuousClock.now + timeout
            var status = ClaudeConnectionStatus.signedOut
            while ContinuousClock.now < deadline {
                do { try await Task.sleep(for: Self.pollInterval) } catch { break }
                // Read before probing: a login that exited before this poll gets one last check, then we stop.
                let exitedBeforeCheck = loginExited.withLock { $0 }
                status = await probe.status()
                if case .connected = status { break }
                if exitedBeforeCheck { break }
            }
            apply(status)
            if !isConnected { hint = "No se completó el inicio de sesión. Probá de nuevo." }
            connectTask = nil
        }
    }

    private func apply(_ status: ClaudeConnectionStatus) {
        checkedAt = .now
        switch status {
        case .notInstalled:
            state = .notInstalled
        case .signedOut:
            state = .signedOut
            hint = nil
        case let .connected(account, method):
            state = .connected(account: account, method: method)
            hint = nil
        }
    }
}
