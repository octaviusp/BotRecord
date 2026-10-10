import SwiftUI

/// The menu-bar glyph for each `StatusDisplay`. Fixed 18 pt tall so the bar never reflows.
struct StatusLabelView: View {
    let display: StatusDisplay

    var body: some View {
        content
            .frame(height: 18)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch display {
        case .idle:
            symbol("record.circle")
        case .selecting:
            symbol("rectangle.dashed")
        case let .countdown(number):
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.22)))
        case let .recording(time):
            capsule(fill: Theme.record, foreground: .white) {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.white).frame(width: 8, height: 8)
                clock(time)
            }
        case let .paused(time):
            capsule(fill: Theme.warning, foreground: .black) {
                Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold))
                clock(time)
            }
        case let .busy(word):
            HStack(spacing: 5) {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                if let word { Text(word).font(.system(size: 12, weight: .medium)) }
            }
        case .error:
            symbol("exclamationmark.triangle").foregroundStyle(Theme.warning)
        case .copied:
            symbol("checkmark.circle.fill").foregroundStyle(Theme.success)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 15, weight: .regular))
    }

    private func clock(_ time: String) -> some View {
        Text(time).font(.system(size: 12, weight: .semibold, design: .monospaced)).monospacedDigit()
    }

    private func capsule<Content: View>(fill: Color, foreground: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5, content: content)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
    }
}
