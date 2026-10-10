import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class MeetingSavedToastModel {
    let meeting: SavedMeeting
    /// Holds the toast open while the pointer is over it.
    var isHovering = false
    @ObservationIgnored var onDismiss: () -> Void = {}
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    private static let lifetime: Duration = .seconds(8)
    private static let hoverRecheck: Duration = .seconds(1)

    init(meeting: SavedMeeting) {
        self.meeting = meeting
    }

    /// "Meeting saved · 42:10"
    var title: String {
        "Meeting saved · \(Formatters.duration(meeting.duration))"
    }

    func startAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task {
            do {
                try await Task.sleep(for: Self.lifetime)
                while isHovering { try await Task.sleep(for: Self.hoverRecheck) }
            } catch { return }
            onDismiss()
        }
    }

    func stopAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = nil
    }

    func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([meeting.folder])
    }
}

/// Bottom-right confirmation after a meeting: what was saved and where it is.
struct MeetingSavedToastView: View {
    let model: MeetingSavedToastModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.wave.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Theme.success.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(model.meeting.folder.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
            // Solid fill: toasts live in non-key panels, where tinted glass buttons wash out to grey.
            Button(action: model.reveal) {
                Label("Show in Finder", systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .contentShape(Capsule())
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: ToastLayout.width)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: ToastLayout.cornerRadius, style: .continuous))
        .onPointerHover { model.isHovering = $0 }
    }
}
