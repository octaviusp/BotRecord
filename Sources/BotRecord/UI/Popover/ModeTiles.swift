import SwiftUI

/// Full screen / Area / Meeting switch drawn as three large tiles.
struct ModeTiles: View {
    @Binding var selection: RecorderMode
    @Namespace private var selectionNamespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 4) {
                tile(.fullScreen, title: "Full screen", symbol: "display")
                tile(.area, title: "Area", symbol: "rectangle.dashed")
                tile(.meeting, title: "Meeting", symbol: "person.2.wave.2")
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.07)))
    }

    private func tile(_ mode: RecorderMode, title: String, symbol: String) -> some View {
        let isSelected = mode == selection
        return Button {
            withAnimation(.snappy(duration: 0.22)) { selection = mode }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(title).font(.system(size: 11, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassEffect(isSelected ? .regular : .identity, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .glassEffectID(mode, in: selectionNamespace)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
