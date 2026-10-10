import CoreMedia

/// ScreenCaptureKit buffers in, one gapless 48 kHz stereo stream out (all sources mixed).
final class MixedAudioPipeline {
    private var converters: [AudioSource: StereoPCMConverter] = [:]
    private let mixer: AudioMixer

    init(sources: Set<AudioSource>) {
        mixer = AudioMixer(sources: sources)
        for source in sources { converters[source] = StereoPCMConverter() }
    }

    /// Returns the newly mixable audio, if any. Buffers from sources not configured are ignored.
    func process(_ sampleBuffer: CMSampleBuffer, from source: AudioSource) throws -> StereoPCMChunk? {
        guard let converter = converters[source] else { return nil }
        let chunk = try converter.convert(sampleBuffer)
        mixer.append(chunk, from: source)
        return mixer.drain()
    }

    func flush() -> StereoPCMChunk? { mixer.flush() }
}
