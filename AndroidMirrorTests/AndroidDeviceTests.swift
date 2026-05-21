import XCTest
@testable import Android_Mirror

/// Tests for AndroidDevice model.
final class AndroidDeviceTests: XCTestCase {

    func testDisplayName_withModel() {
        let device = AndroidDevice(id: "ABC123", model: "Pixel_4a", product: "sunfish", transport: .usb, state: .device)
        XCTAssertEqual(device.displayName, "Pixel_4a")
    }

    func testDisplayName_noModel_fallbackProduct() {
        let device = AndroidDevice(id: "ABC123", model: "", product: "sunfish", transport: .usb, state: .device)
        XCTAssertEqual(device.displayName, "sunfish")
    }

    func testDisplayName_noModel_noProduct_fallbackSerial() {
        let device = AndroidDevice(id: "ABC123", model: "", product: "", transport: .usb, state: .device)
        XCTAssertEqual(device.displayName, "ABC123")
    }

    func testDisplayName_unknownModel_fallbackProduct() {
        let device = AndroidDevice(id: "ABC123", model: "unknown", product: "sunfish", transport: .usb, state: .device)
        XCTAssertEqual(device.displayName, "sunfish")
    }

    func testIsReady_device() {
        let device = AndroidDevice(id: "ABC", model: "", product: "", transport: .usb, state: .device)
        XCTAssertTrue(device.isReady)
    }

    func testIsReady_unauthorized() {
        let device = AndroidDevice(id: "ABC", model: "", product: "", transport: .usb, state: .unauthorized)
        XCTAssertFalse(device.isReady)
    }

    func testIsReady_offline() {
        let device = AndroidDevice(id: "ABC", model: "", product: "", transport: .usb, state: .offline)
        XCTAssertFalse(device.isReady)
    }

    func testSerialEqualsId() {
        let device = AndroidDevice(id: "SER123", model: "", product: "", transport: .usb, state: .device)
        XCTAssertEqual(device.serial, device.id)
    }

    func testTransportUSB() {
        let device = AndroidDevice(id: "SER123", model: "", product: "", transport: .usb, state: .device)
        XCTAssertEqual(device.transport, .usb)
    }

    func testTransportWiFi() {
        let device = AndroidDevice(id: "192.168.1.1:5555", model: "", product: "", transport: .wifi, state: .device)
        XCTAssertEqual(device.transport, .wifi)
    }
}
