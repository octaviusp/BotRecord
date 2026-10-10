import CoreMedia
import Foundation

/// Wraps encoded AV1 temporal units and mixed PCM into CMSampleBuffers for AVAssetWriter.
struct AV1SampleBufferFactory {
    let videoFormat: CMVideoFormatDescription
    let audioFormat: CMAudioFormatDescription

    init(width: Int, height: Int, codecConfiguration: Data) throws {
        // AVAssetWriter passthrough copies `av1C` verbatim into the MP4 sample description.
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["av1C": codecConfiguration],
            kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
            kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_ITU_R_709_2,
            kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2,
            kCMFormatDescriptionExtension_FullRangeVideo: false,
        ]
        var video: CMVideoFormatDescription?
        let videoStatus = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_AV1,
            width: Int32(width), height: Int32(height),
            extensions: extensions as CFDictionary, formatDescriptionOut: &video)
        guard videoStatus == noErr, let video else {
            throw EncodingError.encoderSetup("cannot describe AV1 video for MP4 (OSStatus \(videoStatus))")
        }

        var pcm = AudioStreamBasicDescription(
            mSampleRate: Double(StereoPCMChunk.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var audio: CMAudioFormatDescription?
        let audioStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &pcm, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &audio)
        guard audioStatus == noErr, let audio else {
            throw EncodingError.encoderSetup("cannot describe PCM audio (OSStatus \(audioStatus))")
        }
        videoFormat = video
        audioFormat = audio
    }

    func videoSample(_ packet: EncodedVideoPacket, durationMilliseconds: Int64) throws -> CMSampleBuffer {
        let pts = CMTime(value: packet.ptsMilliseconds, timescale: 1_000)
        var timing = CMSampleTimingInfo(duration: CMTime(value: durationMilliseconds, timescale: 1_000),
                                        presentationTimeStamp: pts, decodeTimeStamp: pts)
        var size = packet.data.count
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: try Self.blockBuffer(packet.data),
            formatDescription: videoFormat, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else {
            throw EncodingError.encoderFailure("cannot wrap AV1 packet (OSStatus \(status))")
        }
        if !packet.isKeyframe, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) {
            let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(first,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return sample
    }

    func audioSample(_ chunk: StereoPCMChunk) throws -> CMSampleBuffer {
        let bytes = chunk.samples.withUnsafeBufferPointer { Data(buffer: $0) }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(StereoPCMChunk.sampleRate)),
            presentationTimeStamp: CMTime(value: chunk.startFrame, timescale: CMTimeScale(StereoPCMChunk.sampleRate)),
            decodeTimeStamp: .invalid)
        var sampleSize = 8
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: try Self.blockBuffer(bytes),
            formatDescription: audioFormat, sampleCount: chunk.frameCount,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample)
        guard status == noErr, let sample else {
            throw EncodingError.encoderFailure("cannot wrap PCM audio (OSStatus \(status))")
        }
        return sample
    }

    private static func blockBuffer(_ data: Data) throws -> CMBlockBuffer {
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: data.count,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
            dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        if status == noErr, let block {
            status = data.withUnsafeBytes { bytes in
                CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block,
                                              offsetIntoDestination: 0, dataLength: data.count)
            }
        }
        guard status == noErr, let block else {
            throw EncodingError.encoderFailure("cannot allocate a media buffer (OSStatus \(status))")
        }
        return block
    }
}
