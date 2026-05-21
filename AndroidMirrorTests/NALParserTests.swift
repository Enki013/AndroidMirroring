import XCTest
@testable import Android_Mirror

/// Tests for NAL unit parsing in ScrcpyRawStreamReader.
/// Covers test plan items: 4A.4, 4A.5, 4A.6, 4A.7
final class NALParserTests: XCTestCase {

    // MARK: - findStartCode

    /// 4A.4: Detect 4-byte start code (00 00 00 01)
    func testFindStartCode4Byte() {
        let bytes: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x65, 0xAB]
        let result = ScrcpyRawStreamReader.findStartCode(in: bytes, from: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offset, 0)
        XCTAssertEqual(result?.length, 4)
    }

    /// 4A.5: Detect 3-byte start code (00 00 01)
    func testFindStartCode3Byte() {
        let bytes: [UInt8] = [0x00, 0x00, 0x01, 0x65, 0xAB]
        let result = ScrcpyRawStreamReader.findStartCode(in: bytes, from: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offset, 0)
        XCTAssertEqual(result?.length, 3)
    }

    /// No start code in random data → nil
    func testNoStartCode() {
        let bytes: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05]
        let result = ScrcpyRawStreamReader.findStartCode(in: bytes, from: 0)
        XCTAssertNil(result)
    }

    /// Start code at non-zero offset
    func testFindStartCodeAtOffset() {
        let bytes: [UInt8] = [0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01, 0x65]
        let result = ScrcpyRawStreamReader.findStartCode(in: bytes, from: 0)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offset, 2)
        XCTAssertEqual(result?.length, 4)
    }

    // MARK: - extractNextNAL

    /// 4A.4: Two NAL units separated by 4-byte start codes
    func testExtractNextNAL_twoUnits4Byte() {
        // [00 00 00 01] [NAL1: 0x67 0xAA 0xBB] [00 00 00 01] [NAL2: 0x68 0xCC]
        var buffer = Data([
            0x00, 0x00, 0x00, 0x01, 0x67, 0xAA, 0xBB,
            0x00, 0x00, 0x00, 0x01, 0x68, 0xCC
        ])

        let nal = ScrcpyRawStreamReader.extractNextNAL(from: &buffer)
        XCTAssertNotNil(nal)
        XCTAssertEqual(nal, Data([0x67, 0xAA, 0xBB]))
        // Buffer should now start with second start code
        XCTAssertEqual(buffer[0], 0x00)
        XCTAssertEqual(buffer[1], 0x00)
        XCTAssertEqual(buffer[2], 0x00)
        XCTAssertEqual(buffer[3], 0x01)
    }

    /// 4A.5: Two NAL units separated by 3-byte start codes
    func testExtractNextNAL_twoUnits3Byte() {
        var buffer = Data([
            0x00, 0x00, 0x01, 0x67, 0xAA,
            0x00, 0x00, 0x01, 0x68, 0xBB
        ])

        let nal = ScrcpyRawStreamReader.extractNextNAL(from: &buffer)
        XCTAssertNotNil(nal)
        XCTAssertEqual(nal, Data([0x67, 0xAA]))
    }

    /// 4A.7: Only one start code → nil (needs more data)
    func testExtractNextNAL_partialData() {
        var buffer = Data([0x00, 0x00, 0x00, 0x01, 0x67, 0xAA, 0xBB])
        let nal = ScrcpyRawStreamReader.extractNextNAL(from: &buffer)
        XCTAssertNil(nal, "Should return nil when only one start code exists (incomplete NAL)")
    }

    /// Mixed 3-byte and 4-byte start codes
    func testExtractNextNAL_mixedStartCodes() {
        var buffer = Data([
            0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x80,  // 4-byte + NAL (3 bytes)
            0x00, 0x00, 0x01, 0x68, 0xCE                 // 3-byte + NAL
        ])

        let nal = ScrcpyRawStreamReader.extractNextNAL(from: &buffer)
        XCTAssertNotNil(nal)
        XCTAssertEqual(nal, Data([0x67, 0x42, 0x80]))
    }

    // MARK: - extractLastNAL

    /// 4A.6: Flush remaining buffer at stream end
    func testExtractLastNAL() {
        var buffer = Data([0x00, 0x00, 0x00, 0x01, 0x65, 0xAA, 0xBB, 0xCC])
        let nal = ScrcpyRawStreamReader.extractLastNAL(from: &buffer)
        XCTAssertNotNil(nal)
        XCTAssertEqual(nal, Data([0x65, 0xAA, 0xBB, 0xCC]))
        XCTAssertTrue(buffer.isEmpty, "Buffer should be cleared after extracting last NAL")
    }

    /// Empty buffer → nil
    func testEmptyBuffer() {
        var buffer = Data()
        XCTAssertNil(ScrcpyRawStreamReader.extractNextNAL(from: &buffer))
        XCTAssertNil(ScrcpyRawStreamReader.extractLastNAL(from: &buffer))
    }
}
