import AVFoundation

/// Streaming sample-rate conversion of mono Float32. One instance per continuous stream: the
/// converter keeps filter state between calls, so consecutive buffers join without clicks.
final class MonoResampler {
    let inputRate: Double
    let outputRate: Double
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?

    init(inputRate: Double, outputRate: Double) throws {
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate, channels: 1, interleaved: false),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outputRate, channels: 1, interleaved: false)
        else { throw EncodingError.audioFormat("cannot describe mono \(inputRate) Hz → \(outputRate) Hz") }
        self.inputRate = inputRate
        self.outputRate = outputRate
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        if inputRate == outputRate {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw EncodingError.audioFormat("cannot resample \(inputRate) Hz to \(outputRate) Hz")
            }
            self.converter = converter
        }
    }

    func resample(_ samples: [Float]) throws -> [Float] {
        guard let converter, !samples.isEmpty else { return samples }
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                            frameCapacity: AVAudioFrameCount(Double(samples.count) * outputRate / inputRate) + 64)
        else { throw EncodingError.audioFormat("cannot allocate resampling buffers") }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            input.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
        }

        var consumed = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow // keep filter state for the next buffer
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw EncodingError.audioFormat("resampling failed: \(conversionError?.localizedDescription ?? "unknown")")
        }
        guard let data = output.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
