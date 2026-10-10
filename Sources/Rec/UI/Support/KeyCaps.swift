import SwiftUI

/// Keyboard shortcut drawn as individual key caps, e.g. ⌃ ⌥ ⌘ R.
struct KeyCaps: View {
    let keys: [String]
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: compact ? 9 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: compact ? 15 : 20, minHeight: compact ? 15 : 20)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .background(RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous).fill(Color.primary.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: compact ? 4 : 5, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }
}
