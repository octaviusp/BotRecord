import SwiftUI

/// "Recording saved" toast: preview, one-tap copy, reveal, optional MP4 copy.
struct SavedToastView: View {
    let model: SavedToastModel

    var body: some View {
        VStack(spacing: 10) {
            ToastThumbnail(model: model)
            header
            primaryActions
            if model.hasCompanion { mp4Button }
            footer
        }
        .padding(10)
        .frame(width: ToastLayout.width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ToastLayout.cornerRadius, style: .continuous))
        .onPointerHover { model.isHovering = $0 }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.success)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.success.opacity(0.18)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording saved").font(.system(size: 13, weight: .semibold))
                Text(model.metaText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: model.onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 2)
    }

    private var primaryActions: some View {
        HStack(spacing: 8) {
            CopyActionButton(
                state: model.copyState,
                idleTitle: "Copy to clipboard",
                copiedTitle: "Copied — paste anywhere",
                action: model.copyFile
            )
            Button(action: model.reveal) {
                Image(systemName: "folder")
                    .font(.system(size: 14))
                    .frame(width: 22, height: 26)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
        }
    }

    private var mp4Button: some View {
        Button(action: model.copyAsMP4) {
            HStack(spacing: 6) {
                Image(systemName: mp4Icon)
                    .foregroundStyle(model.mp4State == .copied ? Theme.success : Color.secondary)
                Text(mp4Title).fontWeight(.semibold)
                if model.mp4State == .idle {
                    Text("for WhatsApp & iMessage").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .disabled(model.mp4State == .working)
        .animation(.snappy(duration: 0.2), value: model.mp4State)
    }

    private var mp4Icon: String {
        switch model.mp4State {
        case .copied: "checkmark"
        case .failed: "exclamationmark.triangle"
        case .idle, .working: "iphone"
        }
    }

    private var mp4Title: String {
        switch model.mp4State {
        case .idle: "Copy as MP4"
        case .working: "Preparing MP4…"
        case .copied: "Copied MP4 — paste anywhere"
        case let .failed(message): message
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw").font(.system(size: 10))
            Text("Drag the preview into any app").font(.system(size: 10.5))
            Spacer(minLength: 0)
            ToastProgressLine(remaining: 1 - model.elapsedFraction).frame(width: 44)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}

enum ToastLayout {
    static let width: CGFloat = 340
    static let cornerRadius: CGFloat = 24
}

private struct ToastProgressLine: View {
    let remaining: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Color.primary.opacity(0.45)).frame(width: proxy.size.width * max(0, remaining))
            }
        }
        .frame(height: 2)
    }
}
