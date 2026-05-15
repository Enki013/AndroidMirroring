import CoreMedia
import Foundation
import VideoToolbox

/// Decodes H.264 NAL units from scrcpy raw video stream via VideoToolbox.
///
/// Expects individual NAL units (without Annex B start codes) from the stream reader.
/// Handles SPS/PPS extraction for format description creation, and converts
/// NAL units to AVCC format (4-byte length prefix) for VideoToolbox.
final class H264Decoder {
    private var session: VTDecompressionSession?
    private var formatDescription: CMFormatDescription?

    /// Stored parameter sets for session creation
    private var spsData: Data?
    private var ppsData: Data?

    var onFrame: ((CVPixelBuffer) -> Void)?

    func decode(nalUnit: Data) {
        guard nalUnit.count > 0 else { return }

        let nalType = nalUnit[0] & 0x1F

        switch nalType {
        case 7: // SPS
            print("[H264Decoder] Got SPS (\(nalUnit.count) bytes)")
            spsData = nalUnit
            tryCreateSession()
            return
        case 8: // PPS
            print("[H264Decoder] Got PPS (\(nalUnit.count) bytes)")
            ppsData = nalUnit
            tryCreateSession()
            return
        case 6: // SEI — skip
            return
        default:
            break
        }

        // For IDR and non-IDR frames, we need a valid session
        guard session != nil else {
            // If we haven't built a session yet, wait for SPS+PPS
            return
        }

        // Convert NAL unit to AVCC format: 4-byte big-endian length prefix + NAL data
        decodeAVCC(nalUnit: nalUnit)
    }

    func invalidate() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
        spsData = nil
        ppsData = nil
    }

    // MARK: - Private

    /// Try to create a decompression session if we have both SPS and PPS.
    private func tryCreateSession() {
        guard let sps = spsData, let pps = ppsData else { return }

        // Invalidate existing session if any
        if let session {
            VTDecompressionSessionInvalidate(session)
            self.session = nil
        }

        guard let fmt = createFormatDescription(sps: sps, pps: pps) else { return }
        self.formatDescription = fmt

        var callback = VTDecompressionOutputCallbackRecord()
        callback.decompressionOutputRefCon = Unmanaged.passUnretained(self).toOpaque()
        callback.decompressionOutputCallback = { refCon, _, status, _, imageBuffer, _, _ in
            if status != noErr {
                print("[H264Decoder] ❌ Decode error: OSStatus \(status)")
                return
            }
            guard let refCon, let imageBuffer else {
                print("[H264Decoder] ⚠️ Decode OK but no image buffer")
                return
            }
            print("[H264Decoder] ✅ Frame decoded: \(CVPixelBufferGetWidth(imageBuffer))x\(CVPixelBufferGetHeight(imageBuffer))")
            let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
            decoder.onFrame?(imageBuffer)
        }

        let attrs: [NSString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
        ]

        var newSession: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: fmt,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &newSession
        )

        if status == noErr {
            self.session = newSession
            print("[H264Decoder] ✅ Decompression session created successfully")
        } else {
            print("[H264Decoder] ❌ Failed to create session: OSStatus \(status)")  
        }
    }

    /// Decode a single NAL unit by wrapping it in AVCC format.
    private func decodeAVCC(nalUnit: Data) {
        guard let session, let formatDescription else { return }

        // Create AVCC data: 4-byte big-endian length + NAL unit
        var avccData = Data(count: 4 + nalUnit.count)
        let length = UInt32(nalUnit.count).bigEndian
        avccData.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: length, as: UInt32.self)
        }
        avccData[4...] = nalUnit[0...]

        guard let blockBuffer = makeBlockBuffer(from: avccData),
              let sampleBuffer = makeSampleBuffer(blockBuffer: blockBuffer, formatDescription: formatDescription) else {
            return
        }

        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._1xRealTimePlayback],
            frameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    private func makeBlockBuffer(from data: Data) -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer?

        let status = CMBlockBufferCreateWithMemoryBlock(
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
        guard status == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                CMBlockBufferReplaceDataBytes(
                    with: base,
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: data.count
                )
            }
        }
        return blockBuffer
    }

    private func makeSampleBuffer(blockBuffer: CMBlockBuffer, formatDescription: CMFormatDescription) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleSize = CMBlockBufferGetDataLength(blockBuffer)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    /// Create an H.264 format description from SPS and PPS parameter sets.
    private func createFormatDescription(sps: Data, pps: Data) -> CMFormatDescription? {
        var description: CMFormatDescription?

        // We need to pass raw parameter set data (without start codes)
        let parameterSets: [Data] = [sps, pps]
        let sizes = parameterSets.map { $0.count }

        // Use withUnsafeBytes to get stable pointers
        return sps.withUnsafeBytes { spsPtr -> CMFormatDescription? in
            pps.withUnsafeBytes { ppsPtr -> CMFormatDescription? in
                guard let spsBase = spsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let ppsBase = ppsPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return nil
                }

                var pointers: [UnsafePointer<UInt8>] = [spsBase, ppsBase]
                var sizes = [sps.count, pps.count]

                let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description
                )
                return status == noErr ? description : nil
            }
        }
    }
}
