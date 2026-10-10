import SwiftUI

/// Meeting mode options: what to record besides every app's audio.
struct MeetingOptionRows: View {
    @Bindable var settings: AppSettings
    let transcription: TranscriptionService
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ToggleRow(icon: "mic", title: "Me (microphone)", isOn: $settings.meetingCaptureMicrophone)
            OptionRow(icon: "waveform.badge.minus", title: "Echo cancellation") {
                PillSegmented(options: EchoCancellationMode.allCases.map { ($0, $0.label) },
                              selection: $settings.meetingEchoCancellation, fontSize: 11.5, horizontalPadding: 9)
            }
            .help(EchoCancellationHint.text(for: settings.meetingEchoCancellation))
            .disabled(!settings.meetingCaptureMicrophone)
            .opacity(settings.meetingCaptureMicrophone ? 1 : 0.4)
            ToggleRow(icon: "display", title: "Record screen", isOn: $settings.meetingRecordScreen)
            TranscriptOptionRow(isOn: $settings.meetingTranscribe, transcription: transcription, onOpenSettings: onOpenSettings)
        }
    }
}

/// What echo cancellation will do for the next meeting, so Auto is never a mystery.
enum EchoCancellationHint {
    static func text(for mode: EchoCancellationMode) -> String {
        switch mode {
        case .auto:
            let route = AudioOutputRoute.current()
            return "Auto: \(mode.isEnabled(for: route) ? "on" : "off") now (\(route.label)). "
                + "On only for the built-in speakers: it lowers the call's volume and costs CPU."
        case .on:
            return "Always on: removes speaker echo from your microphone."
        case .off:
            return "Off: best with headphones."
        }
    }
}
