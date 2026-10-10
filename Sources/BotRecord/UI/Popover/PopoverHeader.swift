import SwiftUI

struct PopoverHeader: View {
    let isFailed: Bool
    let connection: ClaudeConnection
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("BotRecord").font(.system(size: 15, weight: .bold))
            StatusBadge(title: isFailed ? "Error" : "Ready", color: isFailed ? Theme.warning : Theme.success)
            Spacer()
            ClaudeStatusPill(connection: connection)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 4)
    }
}
