import AVFoundation
import CoreMedia

/// Interleaved stereo Float32 at 48 kHz, positioned on the recording timeline.
struct StereoPCMChunk {
    static let sampleRate = 48_000

    /// L,R,L,R… samples.
    var samples: [Float]
    /// Timeline position of the first frame, in 48 kHz frames from recording start.
    var startFrame: Int64

    var frameCount: Int { samples.count / 2 }
}

/// Converts ScreenCaptureKit audio buffers (any LPCM layout the ASBD describes) to `StereoPCMChunk`.
/// One instance per source because resampling is stateful.
final class StereoPCMConverter {
    private var resampler: AVAudioConverter?
    private var resamplerInputRate: Double = 0

    func convert(_ sampleBuffer: CMSampleBuffer) throws -> StereoPCMChunk {
        guard let format = sampleBuffer.formatDescription,
              let asbd = format.audioStreamBasicDescription
        else { throw EncodingError.audioFormat("sample buffer has no audio format description") }
        guard asbd.mFormatID == kAudioFormatLinearPCM else {
            throw EncodingError.audioFormat("expected linear PCM, got format ID \(asbd.mFormatID)")
        }
        let frameCount = sampleBuffer.numSamples
        var stereo = try sampleBuffer.withAudioBufferList { bufferList, _ in
            try Self.interleavedStereo(from: bufferList, asbd: asbd, frameCount: frameCount)
        }
        if asbd.mSampleRate != Double(StereoPCMChunk.sampleRate) {
            stereo = try resample(stereo, from: asbd.mSampleRate)
        }
        let start = sampleBuffer.presentationTimeStamp
        let startSeconds = start.isNumeric ? start.seconds : 0
        return StereoPCMChunk(samples: stereo,
                              startFrame: Int64((startSeconds * Double(StereoPCMChunk.sampleRate)).rounded()))
    }

    private static func interleavedStereo(from bufferList: UnsafeMutableAudioBufferListPointer,
                                          asbd: AudioStreamBasicDescription,
                                          frameCount: Int) throws -> [Float] {
        let isFloat = asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bits = Int(asbd.mBitsPerChannel)
        guard (isFloat && bits == 32) || (!isFloat && bits == 16) else {
            throw EncodingError.audioFormat("\(bits)-bit \(isFloat ? "float" : "integer") PCM")
        }
        let channels = Int(asbd.mChannelsPerFrame)
        guard channels >= 1 else { throw EncodingError.audioFormat("zero channels") }
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0

        // Returns the sample for (frame, channel) regardless of layout or sample type.
        func sample(_ frame: Int, _ channel: Int) -> Float {
            let buffer = bufferList[nonInterleaved ? channel : 0]
            let index = nonInterleaved ? frame : frame * channels + channel
            guard let data = buffer.mData else { return 0 }
            return isFloat
                ? data.assumingMemoryBound(to: Float.self)[index]
                : Float(data.assumingMemoryBound(to: Int16.self)[index]) / 32_768
        }

        let availableFrames = bufferList.map { buffer -> Int in
            let perFrame = Int(asbd.mBytesPerFrame) == 0 ? bits / 8 : Int(asbd.mBytesPerFrame)
            return Int(buffer.mDataByteSize) / perFrame
        }.min() ?? 0
        let frames = min(frameCount, availableFrames)
        var output = [Float](repeating: 0, count: frames * 2)
        let rightChannel = channels > 1 ? 1 : 0 // mono is duplicated to both sides
        for frame in 0..<frames {
            output[frame * 2] = sample(frame, 0)
            output[frame * 2 + 1] = sample(frame, rightChannel)
        }
        return output
    }

    private func resample(_ interleaved: [Float], from inputRate: Double) throws -> [Float] {
        guard let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate,
                                              channels: 2, interleaved: true),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: Double(StereoPCMChunk.sampleRate),
                                               channels: 2, interleaved: true)
        else { throw EncodingError.audioFormat("cannot describe \(inputRate) Hz stereo") }
        if resampler == nil || resamplerInputRate != inputRate {
            resampler = AVAudioConverter(from: inputFormat, to: outputFormat)
            resamplerInputRate = inputRate
        }
        guard let resampler else { throw EncodingError.audioFormat("cannot resample \(inputRate) Hz to 48 kHz") }

        let inputFrames = interleaved.count / 2
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(inputFrames)),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                                            frameCapacity: AVAudioFrameCount(Double(inputFrames) * 48_000 / inputRate) + 64)
        else { throw EncodingError.audioFormat("cannot allocate resampling buffers") }
        input.frameLength = AVAudioFrameCount(inputFrames)
        interleaved.withUnsafeBufferPointer { source in
            input.floatChannelData?[0].update(from: source.baseAddress!, count: interleaved.count)
        }

        var consumed = false
        var conversionError: NSError?
        let status = resampler.convert(to: output, error: &conversionError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow // keep resampler state for the next buffer
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
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength) * 2))
    }
}
