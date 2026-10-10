import SwiftUI

/// Header control: green "Claude" when summaries are available, grey "Connect Claude" (a button) otherwise.
struct ClaudeStatusPill: View {
    let connection: ClaudeConnection

    var body: some View {
        Button(action: connection.connect) {
            HStack(spacing: 5) {
                ClaudeGlyph(size: 11)
                Text(title).font(.system(size: 11, weight: .medium))
                if connection.isConnected {
                    Circle().fill(Theme.success).frame(width: 6, height: 6)
                } else if connection.state == .connecting || connection.state == .checking {
                    ProgressView().controlSize(.mini)
                }
            }
            .foregroundStyle(connection.isConnected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.primary.opacity(connection.isConnected ? 0.08 : 0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isActionable)
        .help(help)
        .accessibilityLabel(help)
    }

    private var title: String {
        switch connection.state {
        case .connected: "Claude"
        case .connecting: "Conectando…"
        case .checking, .notInstalled, .signedOut: "Connect Claude"
        }
    }

    private var isActionable: Bool {
        connection.state == .notInstalled || connection.state == .signedOut
    }

    private var help: String {
        if let hint = connection.hint { return hint }
        switch connection.state {
        case let .connected(account, method): return "Claude conectado (\(method), \(account)): resúmenes disponibles"
        case .notInstalled: return "Instalá Claude Code para generar resúmenes"
        case .signedOut: return "Iniciá sesión en Claude para generar resúmenes"
        case .checking: return "Revisando Claude…"
        case .connecting: return "Terminá de iniciar sesión en el navegador"
        }
    }
}

/// Shown instead of the summary button while Claude isn't connected: what's missing plus the same action.
struct ClaudeConnectPrompt: View {
    let connection: ClaudeConnection

    var body: some View {
        HStack(spacing: 8) {
            ClaudeGlyph(size: 13).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Para generar resúmenes, conectá Claude").font(.system(size: 12, weight: .medium))
                if let hint = connection.hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ClaudeConnectButton(connection: connection)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// "Conectar" / "Instalar" / spinner, shared by the summary prompt and Settings.
struct ClaudeConnectButton: View {
    let connection: ClaudeConnection

    var body: some View {
        switch connection.state {
        case .checking, .connecting:
            ProgressView().controlSize(.small)
        case .notInstalled:
            button("Instalar")
        case .signedOut:
            button("Conectar")
        case .connected:
            EmptyView()
        }
    }

    private func button(_ title: String) -> some View {
        Button(title, action: connection.connect)
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
    }
}
