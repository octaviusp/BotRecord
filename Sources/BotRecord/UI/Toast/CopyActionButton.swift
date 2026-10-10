import SwiftUI

/// Full-width primary button that turns green with a check once the copy succeeded.
/// Solid tint instead of `.glassProminent`/tinted glass: toasts live in non-key panels, where the
/// system styles wash colored buttons out to grey.
struct CopyActionButton: View {
    let state: CopyState
    let idleTitle: String
    let copiedTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Capsule())
            .background(Capsule().fill(tint))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: state)
    }

    private var icon: String {
        switch state {
        case .copied: "checkmark"
        case .failed: "exclamationmark.triangle"
        case .idle, .working: "doc.on.doc"
        }
    }

    private var title: String {
        switch state {
        case .idle, .working: idleTitle
        case .copied: copiedTitle
        case let .failed(message): message
        }
    }

    private var tint: Color {
        switch state {
        case .copied: Theme.success
        case .failed: Theme.warning
        case .idle, .working: Theme.accent
        }
    }
}
