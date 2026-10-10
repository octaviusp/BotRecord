import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let onRequestPermission: () -> Void

    @State private var isPermissionGranted = ScreenCapturePermission.isGranted

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                recordingGroup
                afterRecordingGroup
                shortcutsGroup
                systemGroup
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(minWidth: 520, idealWidth: 520, minHeight: 480, idealHeight: 760)
        .onAppear { settings.refreshLaunchAtLogin() }
        .task { await pollPermission() }
    }

    private var recordingGroup: some View {
        SettingsGroup(title: "Recording") {
            SettingsRow(title: "Save to") {
                HStack(spacing: 8) {
                    Label(settings.outputDirectory.path.abbreviatedPath, systemImage: "folder")
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    Button("Change…", action: chooseOutputDirectory)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            }
            SettingsRow(title: "Resolution", subtitle: "Scaled from your Retina display") {
                PillSegmented(options: VideoResolution.allCases.map { ($0, $0.label) }, selection: $settings.resolution)
            }
            SettingsRow(title: "Frame rate") {
                PillSegmented(options: VideoFrameRate.allCases.map { ($0, $0.label) }, selection: $settings.frameRate)
            }
            SettingsRow(title: "Format", subtitle: "AV1 is ~5× smaller than H.264 at the same quality · H.264 plays everywhere") {
                PillSegmented(
                    options: settings.availableFormats.map { ($0, $0.label) },
                    selection: $settings.format,
                    fontSize: 11.5,
                    horizontalPadding: 9
                )
            }
            SettingsRow(title: "Compression", subtitle: compressionSubtitle) {
                PillSegmented(options: CompressionEffort.allCases.map { ($0, $0.label) }, selection: $settings.compression)
                    .disabled(settings.format == .mp4H264)
                    .opacity(settings.format == .mp4H264 ? 0.4 : 1)
            }
            SettingsRow(title: "Countdown") {
                PillSegmented(
                    options: AppSettings.countdownOptions.map { ($0, $0 == 0 ? "Off" : "\($0) s") },
                    selection: $settings.countdownSeconds
                )
            }
            SettingsToggleRow(title: "Show cursor", isOn: $settings.showCursor)
            SettingsToggleRow(title: "Highlight clicks", isOn: $settings.highlightClicks)
        }
    }

    private var compressionSubtitle: String {
        settings.format == .mp4H264
            ? "Not used for H.264: the hardware encoder is already instant"
            : "Balanced finishes the moment you press Stop"
    }

    private var afterRecordingGroup: some View {
        SettingsGroup(title: "After recording") {
            SettingsToggleRow(title: "Show preview with Copy button", isOn: $settings.showPreview)
            SettingsToggleRow(title: "Copy to clipboard automatically", isOn: $settings.autoCopy)
        }
    }

    private var shortcutsGroup: some View {
        SettingsGroup(title: "Shortcuts") {
            SettingsRow(title: "Start / stop recording") { KeyCaps(keys: GlobalShortcut.toggleRecording.keyCaps) }
            SettingsRow(title: "Record area") { KeyCaps(keys: GlobalShortcut.recordArea.keyCaps) }
            SettingsRow(title: "Cancel selection") { KeyCaps(keys: ["Esc"]) }
        }
    }

    private var systemGroup: some View {
        SettingsGroup(title: "System") {
            SettingsToggleRow(
                title: "Launch at login",
                subtitle: settings.launchAtLoginError,
                isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin)
            )
            SettingsRow(title: "Screen recording permission") {
                if isPermissionGranted {
                    StatusBadge(title: "Granted", color: Theme.success)
                } else {
                    Button("Grant access…", action: onRequestPermission)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                }
            }
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = settings.outputDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.outputDirectory = url
    }

    /// The user flips this in System Settings, so keep the badge honest while the window is open.
    private func pollPermission() async {
        while !Task.isCancelled {
            isPermissionGranted = ScreenCapturePermission.isGranted
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
        }
    }
}
