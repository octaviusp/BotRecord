import SwiftUI

/// "Generar resumen detallado" for the newest meeting, and every state after the press:
/// running (cancellable), done (open / copy) and failed (human message + retry).
/// Summaries need Claude Code, so until it's connected the card offers "Connect Claude" instead.
struct SummaryCard: View {
    let meeting: MeetingEntry
    let summaries: SummaryController
    let connection: ClaudeConnection

    private static let height: CGFloat = 34

    var body: some View {
        Group {
            switch summaries.state(for: meeting) {
            case .idle where connection.isConnected || connection.state == .checking:
                generateButton.disabled(!connection.isConnected)
            case .idle: ClaudeConnectPrompt(connection: connection)
            case .running: runningRow
            case .done: doneRow
            case let .failed(_, message): failedRow(message)
            }
        }
        .animation(.snappy(duration: 0.2), value: summaries.state)
        .animation(.snappy(duration: 0.2), value: connection.state)
    }

    private var generateButton: some View {
        Button { summaries.generate(for: meeting) } label: {
            Label("Generar resumen detallado", systemImage: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: Self.height - 6)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(Theme.accent)
    }

    private var runningRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Generando resumen…").font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
            Button("Cancelar", action: summaries.cancel)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
        .cardChrome(height: Self.height, tint: Theme.accent)
    }

    private var doneRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            Text("Resumen listo").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            Button("Abrir", action: summaries.openSummary)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            Button(action: summaries.copySummary) {
                Label(summaries.didCopy ? "Copiado" : "Copiar", systemImage: summaries.didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .help("Copia summary.md como Markdown")
        }
        .cardChrome(height: Self.height, tint: Theme.success)
    }

    private func failedRow(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Reintentar") { summaries.generate(for: meeting) }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .cardChrome(height: Self.height, tint: Theme.warning)
    }
}

private extension View {
    func cardChrome(height: CGFloat, tint: Color) -> some View {
        padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(RoundedRectangle(cornerRadius: height / 2, style: .continuous).fill(tint.opacity(0.14)))
    }
}
