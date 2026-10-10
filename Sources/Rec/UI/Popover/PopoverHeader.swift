import SwiftUI

struct PopoverHeader: View {
    let isFailed: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Rec").font(.system(size: 15, weight: .bold))
            StatusBadge(title: isFailed ? "Error" : "Ready", color: isFailed ? Theme.warning : Theme.success)
            Spacer()
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
