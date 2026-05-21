import XCTest
@testable import Android_Mirror

/// Tests for ScrcpyControlChannel binary protocol encoding.
/// Covers test plan items: 6.2–6.11, 6.10
final class ControlChannelTests: XCTestCase {

    var channel: ScrcpyControlChannel!

    override func setUp() {
        super.setUp()
        channel = ScrcpyControlChannel()
        channel.videoWidth = 1080
        channel.videoHeight = 2400
    }

    override func tearDown() {
        channel = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Read a big-endian UInt16 from Data at the given offset (alignment-safe).
    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset]) << 8
        let b1 = UInt16(data[offset + 1])
        return b0 | b1
    }

    /// Read a big-endian Int32 from Data at the given offset (alignment-safe).
    private func readInt32(_ data: Data, at offset: Int) -> Int32 {
        let b0 = Int32(data[offset])     << 24
        let b1 = Int32(data[offset + 1]) << 16
        let b2 = Int32(data[offset + 2]) << 8
        let b3 = Int32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }

    // MARK: - Big-Endian Encoding (6.10)

    func testBigEndianUInt64() {
        var data = Data()
        channel.appendUInt64(&data, 0x0102030405060708)
        XCTAssertEqual(data, Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
    }

    func testBigEndianInt32() {
        var data = Data()
        channel.appendInt32(&data, 0x01020304)
        XCTAssertEqual(data, Data([0x01, 0x02, 0x03, 0x04]))
    }

    func testBigEndianInt32_negative() {
        var data = Data()
        channel.appendInt32(&data, -1)
        XCTAssertEqual(data, Data([0xFF, 0xFF, 0xFF, 0xFF]))
    }

    func testBigEndianUInt16() {
        var data = Data()
        channel.appendUInt16(&data, 0x0438)  // 1080
        XCTAssertEqual(data, Data([0x04, 0x38]))
    }

    func testBigEndianInt16() {
        var data = Data()
        channel.appendInt16(&data, -1)
        XCTAssertEqual(data, Data([0xFF, 0xFF]))
    }

    // MARK: - Touch Events

    /// 6.2: Touch DOWN — 32 bytes, type=2, action=0, pressure=0xFFFF
    func testTouchDownPacket() {
        channel.sendTouch(action: .down, x: 540, y: 1200)

        #if DEBUG
        guard let data = channel.lastSentData else {
            XCTFail("No data sent"); return
        }
        XCTAssertEqual(data.count, 32, "Touch packet must be exactly 32 bytes")
        XCTAssertEqual(data[0], 2)  // Type: INJECT_TOUCH_EVENT
        XCTAssertEqual(data[1], 0)  // Action: DOWN

        // Position X at offset 10
        XCTAssertEqual(readInt32(data, at: 10), 540)
        // Position Y at offset 14
        XCTAssertEqual(readInt32(data, at: 14), 1200)
        // Screen Width at offset 18
        XCTAssertEqual(readUInt16(data, at: 18), 1080)
        // Screen Height at offset 20
        XCTAssertEqual(readUInt16(data, at: 20), 2400)
        // Pressure at offset 22: 0xFFFF for down
        XCTAssertEqual(readUInt16(data, at: 22), 0xFFFF)
        // Action Button at offset 24: 1
        XCTAssertEqual(readInt32(data, at: 24), 1)
        // Buttons at offset 28: 1 for down
        XCTAssertEqual(readInt32(data, at: 28), 1)
        #endif
    }

    /// 6.3: Touch UP — pressure=0, buttons=0
    func testTouchUpPacket() {
        channel.sendTouch(action: .up, x: 540, y: 1200)

        #if DEBUG
        guard let data = channel.lastSentData else {
            XCTFail("No data sent"); return
        }
        XCTAssertEqual(data.count, 32)
        XCTAssertEqual(data[1], 1)  // Action: UP
        XCTAssertEqual(readUInt16(data, at: 22), 0, "Pressure should be 0 for up")
        XCTAssertEqual(readInt32(data, at: 28), 0, "Buttons should be 0 for up")
        #endif
    }

    /// 6.4: Touch MOVE — action=2, pressure=0xFFFF
    func testTouchMovePacket() {
        channel.sendTouch(action: .move, x: 600, y: 1300)

        #if DEBUG
        guard let data = channel.lastSentData else {
            XCTFail("No data sent"); return
        }
        XCTAssertEqual(data.count, 32)
        XCTAssertEqual(data[1], 2)  // Action: MOVE
        XCTAssertEqual(readUInt16(data, at: 22), 0xFFFF, "Pressure should be 0xFFFF for move")
        #endif
    }

    // MARK: - Scroll Events

    /// 6.5: Scroll packet — 21 bytes, type=3
    func testScrollPacket() {
        channel.sendScroll(x: 540, y: 1200, hScroll: 0, vScroll: 1.0)

        #if DEBUG
        guard let data = channel.lastSentData else {
            XCTFail("No data sent"); return
        }
        XCTAssertEqual(data.count, 21, "Scroll packet must be exactly 21 bytes")
        XCTAssertEqual(data[0], 3)  // Type: INJECT_SCROLL_EVENT
        XCTAssertEqual(readInt32(data, at: 1), 540) // Position X
        #endif
    }

    /// 6.6: Scroll clamp — extreme values don't overflow
    func testScrollClamp() {
        channel.sendScroll(x: 0, y: 0, hScroll: 100000, vScroll: -100000)
        #if DEBUG
        guard let data = channel.lastSentData else {
            XCTFail("No data sent"); return
        }
        XCTAssertEqual(data.count, 21)
        #endif
    }

    // MARK: - Key Events

    /// 6.7: Keycode packet — 14 bytes, type=0
    func testKeycodeBack() {
        channel.sendKeycode(action: .down, keycode: .back)

        #if DEBUG
        guard let data = channel.lastSentData else {
            XCTFail("No data sent"); return
        }
        XCTAssertEqual(data.count, 14, "Keycode packet must be exactly 14 bytes")
        XCTAssertEqual(data[0], 0)  // Type: INJECT_KEYCODE
        XCTAssertEqual(data[1], 0)  // Action: DOWN
        XCTAssertEqual(readInt32(data, at: 2), 4) // BACK keycode
        XCTAssertEqual(readInt32(data, at: 6), 0) // repeat
        XCTAssertEqual(readInt32(data, at: 10), 0) // metaState
        #endif
    }

    /// 6.8: Back/ScreenOn packet — 2 bytes, type=4
    func testBackOrScreenOn() {
        channel.sendBackOrScreenOn(action: .down)

        #if DEBUG
        guard let data = channel.lastSentData else {
            XCTFail("No data sent"); return
        }
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0], 4)  // Type: BACK_OR_SCREEN_ON
        XCTAssertEqual(data[1], 0)  // Action: DOWN
        #endif
    }

    // MARK: - Guards

    /// 6.9: Zero dimensions → no packet sent
    func testZeroDimensionsGuard() {
        channel.videoWidth = 0
        channel.videoHeight = 0
        channel.sendTouch(action: .down, x: 100, y: 100)
        #if DEBUG
        XCTAssertNil(channel.lastSentData, "Should not send when dimensions are 0")
        #endif
    }

    /// 6.11: Disconnect
    func testDisconnect() {
        channel.disconnect()
        channel.videoWidth = 1080
        channel.videoHeight = 2400
        channel.sendTouch(action: .down, x: 100, y: 100)
        // No crash = success
    }
}
