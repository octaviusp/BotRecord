import SwiftUI

@MainActor @Observable
final class FailureToastModel {
    private(set) var copyState: CopyState = .idle
    let failure: FailurePresentation
    @ObservationIgnored var onDismiss: () -> Void = {}

    init(failure: FailurePresentation) {
        self.failure = failure
    }

    /// "Copy 4:12 clip" when a usable partial file exists.
    var copyTitle: String? {
        failure.partialResult.map { "Copy \(Formatters.duration($0.duration)) clip" }
    }

    func copyPartialClip() {
        guard let partial = failure.partialResult else { return }
        do {
            try FileClipboard.copy(partial.url)
            copyState = .copied
        } catch {
            copyState = .failed(error.localizedDescription)
        }
    }
}

/// Top-right toast shown when a recording could not start or stopped early.
struct FailureToastView: View {
    let model: FailureToastModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Theme.warning)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.warning.opacity(0.18)))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.failure.title).font(.system(size: 13, weight: .semibold))
                Text(model.failure.message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions.padding(.top, 6)
            }
        }
        .padding(12)
        .frame(width: ToastLayout.width, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button("Dismiss", action: model.onDismiss)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            if let title = model.copyTitle {
                CopyActionButton(
                    state: model.copyState,
                    idleTitle: title,
                    copiedTitle: "Copied",
                    action: model.copyPartialClip
                )
                .fixedSize()
            }
        }
    }
}
