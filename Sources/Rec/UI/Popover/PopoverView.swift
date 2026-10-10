import SwiftUI

/// The recorder popover: choose a mode and its options, press the big red button.
struct PopoverView: View {
    @Bindable var settings: AppSettings
    let sessions: CaptureSessions
    let recents: RecentRecordingsStore
    let onRecord: () -> Void
    let onOpenSettings: () -> Void
    /// Rows change with the mode and the summary card grows; the panel re-anchors under the menu bar.
    let onContentSizeChange: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            PopoverHeader(isFailed: sessions.isFailed, onOpenSettings: onOpenSettings)
            ModeTiles(selection: $settings.recorderMode)
            if settings.recorderMode == .meeting {
                MeetingOptionRows(settings: settings,
                                  transcription: sessions.transcription, onOpenSettings: onOpenSettings)
            } else {
                screenOptionRows
            }
            RecordButton(title: recordTitle, action: onRecord)
            shortcutHint
            Divider().opacity(0.5)
            RecentSection(recents: recents, summaries: sessions.summaries, transcription: sessions.transcription,
                          folder: browsedFolder)
            PopoverFooter(outputDirectory: browsedFolder)
        }
        .padding(14)
        .frame(width: Theme.popoverWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { _ in onContentSizeChange() }
    }

    private var recordTitle: String {
        switch settings.recorderMode {
        case .fullScreen: "Record full screen"
        case .area: "Select area & record"
        case .meeting: "Start meeting notes"
        }
    }

    /// The folder that "Open folder" and the footer point at: the library while in meeting mode.
    private var browsedFolder: URL {
        settings.recorderMode == .meeting ? settings.libraryDirectory : settings.outputDirectory
    }

    private var screenOptionRows: some View {
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
            if settings.captureMicrophone || settings.captureSystemAudio {
                TranscriptOptionRow(isOn: $settings.transcribeRecordings, transcription: sessions.transcription,
                                    onOpenSettings: onOpenSettings)
            }
        }
    }

    private var shortcutHint: some View {
        let shortcut: GlobalShortcut = settings.recorderMode == .meeting ? .toggleMeeting : .toggleRecording
        return HStack(spacing: 8) {
            KeyCaps(keys: shortcut.keyCaps, compact: true)
            Text("start / stop from anywhere")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }
}
