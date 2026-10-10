import SwiftUI

/// Icon + label on the left, a control on the right.
struct OptionRow<Control: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            control()
        }
        .frame(height: Theme.rowHeight)
        .padding(.horizontal, 4)
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        OptionRow(icon: icon, title: title) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
