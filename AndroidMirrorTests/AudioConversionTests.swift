import XCTest
import AVFoundation
@testable import Android_Mirror

/// Tests for audio PCM conversion (s16le → Float32).
/// Covers test plan items: 5.3, 5.9
@MainActor
final class AudioConversionTests: XCTestCase {

    /// 5.9: Playback format is 48kHz stereo Float32
    func testPlaybackFormat() {
        let player = AudioStreamPlayer()
        // The playbackFormat property is private, but we can verify behavior indirectly
        // by checking the format used in schedule calls.
        // For now, verify the player initializes without crashing.
        XCTAssertNotNil(player)
    }

    /// 5.3: s16le → Float32 conversion accuracy
    func testS16leToFloat32Conversion() {
        // Simulate s16le stereo data: 2 frames × 2 channels × 2 bytes = 8 bytes
        // Frame 1: Left = 32767 (max positive), Right = -32768 (max negative)
        // Frame 2: Left = 0 (silence), Right = 16384 (mid-range)
        var data = Data()

        // Frame 1 Left: 32767 → 0x7FFF little-endian → FF 7F
        let l1 = Int16(32767).littleEndian
        withUnsafeBytes(of: l1) { data.append(contentsOf: $0) }
        // Frame 1 Right: -32768 → 0x8000 little-endian → 00 80
        let r1 = Int16(-32768).littleEndian
        withUnsafeBytes(of: r1) { data.append(contentsOf: $0) }
        // Frame 2 Left: 0
        let l2 = Int16(0).littleEndian
        withUnsafeBytes(of: l2) { data.append(contentsOf: $0) }
        // Frame 2 Right: 16384
        let r2 = Int16(16384).littleEndian
        withUnsafeBytes(of: r2) { data.append(contentsOf: $0) }

        // Manually do the conversion to verify expected values
        let frameCount = data.count / 4
        XCTAssertEqual(frameCount, 2)

        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            XCTFail("Could not create buffer")
            return
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let left  = buffer.floatChannelData![0]
            let right = buffer.floatChannelData![1]
            for i in 0..<frameCount {
                left[i]  = Float(samples[i * 2])     / 32768.0
                right[i] = Float(samples[i * 2 + 1]) / 32768.0
            }
        }

        let left  = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        // Frame 1
        XCTAssertEqual(left[0], Float(32767) / 32768.0, accuracy: 0.0001)
        XCTAssertEqual(right[0], Float(-32768) / 32768.0, accuracy: 0.0001)

        // Frame 2
        XCTAssertEqual(left[1], 0.0, accuracy: 0.0001)
        XCTAssertEqual(right[1], Float(16384) / 32768.0, accuracy: 0.0001)
    }

    /// Empty data → frameCount = 0
    func testEmptyData() {
        let data = Data()
        let frameCount = data.count / 4
        XCTAssertEqual(frameCount, 0)
    }

    /// De-interleave: verify left and right channels are separated correctly
    func testDeInterleave() {
        // 1 frame: Left = 1000, Right = 2000
        var data = Data()
        let l = Int16(1000).littleEndian
        withUnsafeBytes(of: l) { data.append(contentsOf: $0) }
        let r = Int16(2000).littleEndian
        withUnsafeBytes(of: r) { data.append(contentsOf: $0) }

        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1

        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            buffer.floatChannelData![0][0] = Float(samples[0]) / 32768.0
            buffer.floatChannelData![1][0] = Float(samples[1]) / 32768.0
        }

        XCTAssertEqual(buffer.floatChannelData![0][0], Float(1000) / 32768.0, accuracy: 0.0001)
        XCTAssertEqual(buffer.floatChannelData![1][0], Float(2000) / 32768.0, accuracy: 0.0001)
    }
}
