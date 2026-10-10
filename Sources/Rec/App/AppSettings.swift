import Foundation
import Observation
import ServiceManagement

/// User preferences, persisted to UserDefaults on every change so the next launch matches.
@MainActor @Observable
final class AppSettings {
    static let defaultOutputDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Movies/general/screen-recordings", isDirectory: true)

    var mode: CaptureMode { didSet { persist(mode, Key.mode) } }
    var resolution: VideoResolution { didSet { persist(resolution, Key.resolution) } }
    var frameRate: VideoFrameRate { didSet { persist(frameRate, Key.frameRate) } }
    var format: OutputFormat { didSet { persist(format, Key.format) } }
    var compression: CompressionEffort { didSet { persist(compression, Key.compression) } }
    var countdownSeconds: Int { didSet { defaults.set(countdownSeconds, forKey: Key.countdownSeconds) } }
    var showCursor: Bool { didSet { defaults.set(showCursor, forKey: Key.showCursor) } }
    var highlightClicks: Bool { didSet { defaults.set(highlightClicks, forKey: Key.highlightClicks) } }
    var captureMicrophone: Bool { didSet { defaults.set(captureMicrophone, forKey: Key.captureMicrophone) } }
    var captureSystemAudio: Bool { didSet { defaults.set(captureSystemAudio, forKey: Key.captureSystemAudio) } }
    var showPreview: Bool { didSet { defaults.set(showPreview, forKey: Key.showPreview) } }
    var autoCopy: Bool { didSet { defaults.set(autoCopy, forKey: Key.autoCopy) } }
    var outputDirectory: URL { didSet { defaults.set(outputDirectory.path, forKey: Key.outputDirectory) } }

    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginError: String?

    static let countdownOptions = [0, 3, 5]

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.enumValue(Key.mode, default: .fullScreen)
        resolution = defaults.enumValue(Key.resolution, default: .p1080)
        frameRate = defaults.enumValue(Key.frameRate, default: .fps60)
        compression = defaults.enumValue(Key.compression, default: .balanced)
        let storedFormat: OutputFormat = defaults.enumValue(Key.format, default: .webmAV1)
        format = storedFormat == .mp4AV1 && !MP4AV1Writer.isSupported ? .mp4H264 : storedFormat
        countdownSeconds = defaults.object(forKey: Key.countdownSeconds) as? Int ?? 3
        showCursor = defaults.object(forKey: Key.showCursor) as? Bool ?? true
        highlightClicks = defaults.object(forKey: Key.highlightClicks) as? Bool ?? false
        captureMicrophone = defaults.object(forKey: Key.captureMicrophone) as? Bool ?? false
        captureSystemAudio = defaults.object(forKey: Key.captureSystemAudio) as? Bool ?? false
        showPreview = defaults.object(forKey: Key.showPreview) as? Bool ?? true
        autoCopy = defaults.object(forKey: Key.autoCopy) as? Bool ?? false
        outputDirectory = defaults.string(forKey: Key.outputDirectory)
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultOutputDirectory
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Formats offered in pickers; MP4 · AV1 appears only where the system can write it.
    var availableFormats: [OutputFormat] {
        OutputFormat.allCases.filter { $0 != .mp4AV1 || MP4AV1Writer.isSupported }
    }

    /// The popover's two-way WebM/MP4 switch. Choosing MP4 keeps AV1 when settings already picked it.
    var usesMP4Container: Bool {
        get { format != .webmAV1 }
        set { format = newValue ? (format == .mp4AV1 ? .mp4AV1 : .mp4H264) : .webmAV1 }
    }

    var recordingOptions: RecordingOptions {
        RecordingOptions(
            resolution: resolution,
            frameRate: frameRate,
            format: format,
            compression: compression,
            showCursor: showCursor,
            highlightClicks: highlightClicks,
            captureMicrophone: captureMicrophone,
            captureSystemAudio: captureSystemAudio,
            outputDirectory: outputDirectory
        )
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    /// The user can flip this in System Settings, so re-read it whenever the window appears.
    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func persist<T: RawRepresentable>(_ value: T, _ key: String) {
        defaults.set(value.rawValue, forKey: key)
    }

    private enum Key {
        static let mode = "mode"
        static let resolution = "resolution"
        static let frameRate = "frameRate"
        static let format = "format"
        static let compression = "compression"
        static let countdownSeconds = "countdownSeconds"
        static let showCursor = "showCursor"
        static let highlightClicks = "highlightClicks"
        static let captureMicrophone = "captureMicrophone"
        static let captureSystemAudio = "captureSystemAudio"
        static let showPreview = "showPreview"
        static let autoCopy = "autoCopy"
        static let outputDirectory = "outputDirectory"
    }
}

private extension UserDefaults {
    func enumValue<T: RawRepresentable>(_ key: String, default fallback: T) -> T {
        (object(forKey: key) as? T.RawValue).flatMap(T.init(rawValue:)) ?? fallback
    }
}
