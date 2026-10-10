import SwiftUI

@MainActor @Observable
final class RecordingHUDModel {
    /// Whole seconds only: the label never shows more, so sub-second updates would just re-render for nothing.
    var elapsedSeconds = 0
    var isPaused = false
    let actions: RecordingHUDActions

    init(actions: RecordingHUDActions) {
        self.actions = actions
    }
}

enum ElapsedTimeFormat {
    /// "00:42", or "1:02:03" once past an hour.
    static func string(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds % 3600 / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

/// Floating glass capsule: recording state, elapsed time and the pause / discard / stop controls.
struct RecordingHUDView: View {
    let model: RecordingHUDModel

    var body: some View {
        HStack(spacing: 12) {
            RecordingIndicator(isPaused: model.isPaused)
            timer
            Divider().frame(height: 22)
            HStack(spacing: 4) {
                HUDIconButton(
                    symbol: model.isPaused ? "play.fill" : "pause.fill",
                    label: model.isPaused ? "Resume recording" : "Pause recording",
                    action: model.isPaused ? model.actions.resume : model.actions.pause
                )
                HUDIconButton(symbol: "trash", label: "Discard recording", action: model.actions.discard)
                HUDStopButton(action: model.actions.stop)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
        .padding(OverlayMetrics.shadowInset)
    }

    private var timer: some View {
        VStack(spacing: 0) {
            // Always laid out so pausing never shifts the controls.
            Text("PAUSED")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.warning)
                .opacity(model.isPaused ? 1 : 0)
            Text(ElapsedTimeFormat.string(seconds: model.elapsedSeconds))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(model.isPaused ? .secondary : .primary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pulsing red dot while recording; static amber while paused.
private struct RecordingIndicator: View {
    private static let pulsePeriod = 1.6

    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused)) { context in
            let pulse = isPaused ? 0 : 0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 2 * .pi / Self.pulsePeriod)
            ZStack {
                Circle()
                    .fill(Theme.record.opacity(0.3 * (1 - pulse)))
                    .frame(width: 10 + 10 * pulse, height: 10 + 10 * pulse)
                Circle()
                    .fill(isPaused ? Theme.warning : Theme.record)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 20, height: 20)
        }
        .accessibilityLabel(isPaused ? "Paused" : "Recording")
    }
}

private struct HUDIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.primary.opacity(isHovering ? 0.14 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct HUDStopButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white)
                .frame(width: 12, height: 12)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.record).brightness(isHovering ? 0.08 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Stop and save")
        .accessibilityLabel("Stop recording")
    }
}
