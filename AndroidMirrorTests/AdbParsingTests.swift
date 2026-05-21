import XCTest
@testable import Android_Mirror

/// Tests for ADB device output parsing.
/// Covers test plan items: 2.4, 2.6
final class AdbParsingTests: XCTestCase {

    let adb = AdbService.shared

    /// 2.6: Parse USB device with model
    func testParseUSBDevice() async {
        let lines = [
            "List of devices attached",
            "ABCD1234   device usb:1-1 product:sunfish model:Pixel_4a transport_id:1"
        ]
        let devices = await adb.parseDevices(lines: lines)
        XCTAssertEqual(devices.count, 1)

        let d = devices[0]
        XCTAssertEqual(d.serial, "ABCD1234")
        XCTAssertEqual(d.state, .device)
        XCTAssertEqual(d.transport, .usb)
        XCTAssertEqual(d.model, "Pixel_4a")
        XCTAssertEqual(d.product, "sunfish")
    }

    /// 2.6: Parse WiFi device (serial contains ":")
    func testParseWiFiDevice() async {
        let lines = [
            "List of devices attached",
            "192.168.1.100:5555   device product:raven model:Pixel_6_Pro transport_id:2"
        ]
        let devices = await adb.parseDevices(lines: lines)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].transport, .wifi)
        XCTAssertEqual(devices[0].serial, "192.168.1.100:5555")
    }

    /// 2.4: Parse unauthorized device
    func testParseUnauthorized() async {
        let lines = [
            "List of devices attached",
            "XYZ789   unauthorized transport_id:3"
        ]
        let devices = await adb.parseDevices(lines: lines)
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].state, .unauthorized)
    }

    /// 2.6: Multiple devices
    func testParseMultipleDevices() async {
        let lines = [
            "List of devices attached",
            "SERIAL1   device model:Phone1 product:prod1",
            "SERIAL2   offline model:Phone2 product:prod2",
            "192.168.1.50:5555   device model:Phone3 product:prod3"
        ]
        let devices = await adb.parseDevices(lines: lines)
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].state, .device)
        XCTAssertEqual(devices[1].state, .offline)
        XCTAssertEqual(devices[2].transport, .wifi)
    }

    /// Empty output
    func testEmptyOutput() async {
        let lines = [
            "List of devices attached",
            ""
        ]
        let devices = await adb.parseDevices(lines: lines)
        XCTAssertTrue(devices.isEmpty)
    }
}
