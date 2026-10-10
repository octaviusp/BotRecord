import Foundation

/// One output file and the sink writing it.
struct SinkOutput {
    let sink: MediaSink
    let url: URL
}

/// The main output chosen by the user's format, plus a hardware H.264 companion when the main
/// file is not already H.264 (it backs "Copy as MP4" at almost no cost).
struct RecordingSinks {
    let main: SinkOutput
    let companion: SinkOutput?
    /// The format actually recorded, which differs from the request when AV1 in MP4 is unsupported.
    let format: OutputFormat
    let encodeConfig: VideoEncodeConfig

    var all: [MediaSink] { [main.sink] + (companion.map { [$0.sink] } ?? []) }

    static func make(options: RecordingOptions, outputSize: CaptureGeometry.PixelSize) throws -> RecordingSinks {
        let format = resolvedFormat(options.format)
        var audioSources = Set<AudioSource>()
        if options.captureSystemAudio { audioSources.insert(.system) }
        if options.captureMicrophone { audioSources.insert(.microphone) }
        let config = VideoEncodeConfig(
            width: outputSize.width,
            height: outputSize.height,
            frameRate: options.frameRate.rawValue,
            compression: options.compression,
            audioSources: audioSources
        )

        let mainURL = try OutputNaming.mainOutputURL(directory: options.outputDirectory, format: format)
        let mainSink = try makeMainSink(format: format, url: mainURL, config: config)
        guard format != .mp4H264 else {
            return RecordingSinks(main: SinkOutput(sink: mainSink, url: mainURL), companion: nil, format: format, encodeConfig: config)
        }

        do {
            let companionURL = try OutputNaming.companionURL(forMainOutput: mainURL)
            let companionSink = try MP4Writer(url: companionURL, config: config, includeAudio: true)
            return RecordingSinks(
                main: SinkOutput(sink: mainSink, url: mainURL),
                companion: SinkOutput(sink: companionSink, url: companionURL),
                format: format,
                encodeConfig: config
            )
        } catch {
            mainSink.cancel()
            throw error
        }
    }

    func cancelAll() {
        all.forEach { $0.cancel() }
    }

    /// Finalizes every sink concurrently. A failure in one never prevents the others from finishing.
    func finishAll() async -> (main: Result<Void, Error>, companion: Result<Void, Error>?) {
        async let mainResult = Self.settle(main.sink)
        guard let companion else { return (await mainResult, nil) }
        async let companionResult = Self.settle(companion.sink)
        return (await mainResult, await companionResult)
    }

    private static func settle(_ sink: MediaSink) async -> Result<Void, Error> {
        do {
            try await sink.finish()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private static func resolvedFormat(_ requested: OutputFormat) -> OutputFormat {
        if requested == .mp4AV1, !MP4AV1Writer.isSupported {
            captureLog.error("MP4 with AV1 is not supported on this Mac; recording H.264 instead")
            return .mp4H264
        }
        return requested
    }

    private static func makeMainSink(format: OutputFormat, url: URL, config: VideoEncodeConfig) throws -> MediaSink {
        switch format {
        case .webmAV1: try WebMAV1Writer(url: url, config: config)
        case .mp4AV1: try MP4AV1Writer(url: url, config: config)
        case .mp4H264: try MP4Writer(url: url, config: config, includeAudio: !config.audioSources.isEmpty)
        }
    }
}
