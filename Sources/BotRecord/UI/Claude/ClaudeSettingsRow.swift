import SwiftUI

/// Settings → Meetings: whether summaries can use Claude Code, with Connect and Re-check.
struct ClaudeSettingsRow: View {
    let connection: ClaudeConnection

    var body: some View {
        SettingsRow(title: "Claude (summaries)", subtitle: subtitle) {
            HStack(spacing: 8) {
                status
                ClaudeConnectButton(connection: connection)
                if connection.state != .checking && connection.state != .connecting {
                    Button("Re-check", action: connection.refresh)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.small)
                }
            }
        }
        .onAppear { connection.refreshIfStale() }
    }

    @ViewBuilder private var status: some View {
        switch connection.state {
        case .connected: StatusBadge(title: "Connected", color: Theme.success)
        case .notInstalled: StatusBadge(title: "Not installed", color: .secondary)
        case .signedOut: StatusBadge(title: "Signed out", color: .secondary)
        case .checking, .connecting: EmptyView()
        }
    }

    private var subtitle: String {
        if let hint = connection.hint { return hint }
        switch connection.state {
        case let .connected(account, method):
            return account == ClaudeAccount.defaultLogin.label ? "Signed in with \(method)" : "Signed in with \(method) · \(account)"
        case .notInstalled: return "Summaries run through your own Claude Code. Transcripts stay local either way."
        case .signedOut: return "Sign in to Claude Code to generate meeting summaries"
        case .checking: return "Checking…"
        case .connecting: return "Finish signing in in your browser"
        }
    }
}
