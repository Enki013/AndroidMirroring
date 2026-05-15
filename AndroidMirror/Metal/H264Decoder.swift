import CoreMedia
import Foundation
import VideoToolbox

/// Decodes H.264 NAL units from scrcpy video stream via VideoToolbox.
final class H264Decoder {
    private var session: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?

    var onFrame: ((CVPixelBuffer) -> Void)?

    func decode(nalUnit: Data) {
        guard !nalUnit.isEmpty else { return }
        ensureSession(with: nalUnit)
        guard let session, let block = makeBlockBuffer(from: nalUnit),
              let sample = makeSampleBuffer(blockBuffer: block) else { return }

        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sample,
            flags: [],
            frameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
    }

    private func ensureSession(with nalUnit: Data) {
        guard session == nil else { return }
        guard let formatDescription = createFormatDescription(from: nalUnit) else { return }
        self.formatDescription = formatDescription

        var callback = VTDecompressionOutputCallbackRecord()
        callback.decompressionOutputRefCon = Unmanaged.passUnretained(self).toOpaque()
        callback.decompressionOutputCallback = { refCon, _, status, _, imageBuffer, _, _ in
            guard status == noErr, let refCon, let imageBuffer else { return }
            let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
            decoder.onFrame?(imageBuffer)
        }

        let attrs: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]
        VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
    }

    private func makeBlockBuffer(from data: Data) -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer?
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return -1 }
            return CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: 0,
                blockBufferOut: &blockBuffer
            )
        }
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                CMBlockBufferReplaceDataBytes(
                    with: base.assumingMemoryBound(to: UInt8.self),
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: data.count
                )
            }
        }
        return blockBuffer
    }

    private func makeSampleBuffer(blockBuffer: CMBlockBuffer) -> CMSampleBuffer? {
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    private func createFormatDescription(from nalUnit: Data) -> CMFormatDescription? {
        let sets = extractParameterSets(from: nalUnit)
        guard sets.count >= 2 else { return nil }

        var description: CMFormatDescription?
        var sizes = sets.map { $0.count }
        var pointers: [UnsafePointer<UInt8>] = sets.map { $0.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! } }

        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: sets.count,
            parameterSetPointers: &pointers,
            parameterSetSizes: &sizes,
            nalUnitHeaderLength: 4,
            formatDescriptionOut: &description
        )
        return status == noErr ? description : nil
    }

    private func extractParameterSets(from data: Data) -> [Data] {
        var sets: [Data] = []
        let bytes = [UInt8](data)
        var i = 0
        while i + 4 < bytes.count {
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                let start = i + 3
                let nalType = bytes[start] & 0x1F
                if nalType == 7 || nalType == 8 {
                    var end = start + 1
                    while end + 3 < bytes.count {
                        if bytes[end] == 0, bytes[end + 1] == 0, bytes[end + 2] == 1 { break }
                        end += 1
                    }
                    sets.append(Data(bytes[start..<end]))
                }
                i = start
            }
            i += 1
        }
        return sets
    }
}
