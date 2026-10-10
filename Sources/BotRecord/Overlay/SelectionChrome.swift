import SwiftUI

/// Padding around glass surfaces so their shadow is not clipped by the hosting view.
enum OverlayMetrics {
    static let shadowInset: CGFloat = 16
}

/// Keyboard-key glyph used in hints ("Esc", "Space").
struct OverlayKeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.primary.opacity(0.14)))
    }
}

/// Initial-state instruction pill at the top of every screen.
struct SelectionHintView: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Drag to select an area")
            separator
            HStack(spacing: 6) { OverlayKeyCap(label: "Space"); Text("Full screen") }
            separator
            HStack(spacing: 6) { OverlayKeyCap(label: "Esc"); Text("Cancel") }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .padding(OverlayMetrics.shadowInset)
    }

    private var separator: some View {
        Text("·").foregroundStyle(.secondary)
    }
}

/// Card shown over a display when hovering it with several displays connected.
struct SelectionDisplayCard: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(spacing: 3) {
            Text(name).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(OverlayMetrics.shadowInset)
    }
}

@MainActor @Observable
final class SelectionToolbarModel {
    var aspect: AspectPreset = .free
    var canRecord = true
    let qualityBadge: String
    var onSelectAspect: (AspectPreset) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onRecord: () -> Void = {}

    init(qualityBadge: String) {
        self.qualityBadge = qualityBadge
    }
}

/// Glass capsule under the selection: aspect presets, quality, cancel and record.
struct SelectionToolbarView: View {
    let model: SelectionToolbarModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AspectPreset.allCases) { preset in aspectPill(preset) }
            }
            Divider().frame(height: 20)
            Text(model.qualityBadge)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(.primary.opacity(0.08)))
            Spacer(minLength: 20)
            cancelButton
            recordButton
        }
        .padding(8)
        .glassEffect(.regular, in: .capsule)
        .padding(OverlayMetrics.shadowInset)
    }

    private func aspectPill(_ preset: AspectPreset) -> some View {
        let isSelected = model.aspect == preset
        return Button { model.onSelectAspect(preset) } label: {
            Text(preset.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background { if isSelected { Capsule().strokeBorder(.primary.opacity(0.75), lineWidth: 1) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aspect ratio \(preset.title)")
    }

    private var cancelButton: some View {
        Button(action: model.onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.primary.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Cancel (Esc)")
        .accessibilityLabel("Cancel")
    }

    private var recordButton: some View {
        Button(action: model.onRecord) {
            HStack(spacing: 7) {
                Circle().fill(.white).frame(width: 8, height: 8)
                Text("Record area").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Capsule().fill(Theme.record))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(model.canRecord ? 1 : 0.4)
        .disabled(!model.canRecord)
        .help(model.canRecord ? "Record area (Return)" : "Select at least \(SelectionLimits.minimumPixelSize.width) × \(SelectionLimits.minimumPixelSize.height) px")
    }
}
