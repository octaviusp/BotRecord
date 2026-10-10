import SwiftUI

/// The recorder popover: choose mode and quality, press the big red button.
struct PopoverView: View {
    @Bindable var settings: AppSettings
    let coordinator: RecordingCoordinator
    let recents: RecentRecordingsStore
    let onRecord: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            PopoverHeader(isFailed: coordinator.phase == .failed, onOpenSettings: onOpenSettings)
            ModeTiles(selection: $settings.mode)
            optionRows
            RecordButton(title: recordTitle, action: onRecord)
            shortcutHint
            Divider().opacity(0.5)
            RecentSection(recents: recents, outputDirectory: settings.outputDirectory)
            PopoverFooter(outputDirectory: settings.outputDirectory)
        }
        .padding(14)
        .frame(width: Theme.popoverWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    private var recordTitle: String {
        settings.mode == .fullScreen ? "Record full screen" : "Select area & record"
    }

    private var optionRows: some View {
        VStack(spacing: 2) {
            OptionRow(icon: "arrow.up.left.and.arrow.down.right", title: "Quality") {
                PillSegmented(
                    options: VideoResolution.allCases.map { ($0, $0.label) },
                    selection: $settings.resolution
                )
            }
            OptionRow(icon: "speedometer", title: "Frame rate") {
                PillSegmented(
                    options: VideoFrameRate.allCases.map { ($0, $0.label) },
                    selection: $settings.frameRate
                )
            }
            OptionRow(icon: "film", title: "Format") {
                PillSegmented(
                    options: [(false, OutputFormat.webmAV1.containerLabel), (true, OutputFormat.mp4H264.containerLabel)],
                    selection: $settings.usesMP4Container
                )
            }
            ToggleRow(icon: "mic", title: "Microphone", isOn: $settings.captureMicrophone)
            ToggleRow(icon: "speaker.wave.2", title: "System audio", isOn: $settings.captureSystemAudio)
        }
    }

    private var shortcutHint: some View {
        HStack(spacing: 8) {
            KeyCaps(keys: GlobalShortcut.toggleRecording.keyCaps, compact: true)
            Text("start / stop from anywhere")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
