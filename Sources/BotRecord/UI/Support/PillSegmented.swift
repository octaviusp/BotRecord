import SwiftUI

/// Compact segmented control: a quiet track with a Liquid Glass pill that slides to the selection.
struct PillSegmented<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var fontSize: CGFloat = 12
    var horizontalPadding: CGFloat = 11

    @Namespace private var selectionNamespace

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(options, id: \.value) { option in
                    segment(option.value, title: option.title)
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .fixedSize()
    }

    private func segment(_ value: Value, title: String) -> some View {
        let isSelected = value == selection
        return Button {
            withAnimation(.snappy(duration: 0.22)) { selection = value }
        } label: {
            Text(title)
                .font(.system(size: fontSize, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 5)
                .contentShape(Capsule())
                .glassEffect(isSelected ? .regular : .identity, in: Capsule())
                .glassEffectID(value, in: selectionNamespace)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
