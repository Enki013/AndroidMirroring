import Foundation
import Network

/// Handles the scrcpy control socket connection and sends input events to the device.
///
/// Binary protocol reference (scrcpy 4.0):
///   Touch: type(1) + action(1) + pointerId(8) + x(4) + y(4) + screenW(2) + screenH(2) + pressure(2) + actionButton(4) + buttons(4) = 32 bytes
///   Keycode: type(1) + action(1) + keycode(4) + repeat(4) + metaState(4) = 14 bytes
///   Scroll: type(1) + x(4) + y(4) + screenW(2) + screenH(2) + hScroll(2) + vScroll(2) + buttons(4) = 21 bytes
final class ScrcpyControlChannel: @unchecked Sendable {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "scrcpy.control", qos: .userInteractive)

    /// The video frame dimensions, used for coordinate mapping
    var videoWidth: UInt16 = 0
    var videoHeight: UInt16 = 0

    /// Connect to the control socket at the given port.
    /// Must be called AFTER the video connection is established (scrcpy expects video first).
    func connect(port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        let conn = NWConnection(
            to: .hostPort(host: .ipv4(.loopback), port: nwPort),
            using: .tcp
        )

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[ControlChannel] Connected!")
            case .failed(let error):
                print("[ControlChannel] Failed: \(error)")
            case .cancelled:
                print("[ControlChannel] Cancelled")
            default:
                break
            }
        }

        conn.start(queue: queue)
        self.connection = conn
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - Touch Events

    /// Action constants matching Android's MotionEvent
    enum TouchAction: UInt8 {
        case down = 0
        case up = 1
        case move = 2
    }

    /// Send a touch event to the device.
    /// - Parameters:
    ///   - action: down, up, or move
    ///   - x: X coordinate in video frame space (0..videoWidth)
    ///   - y: Y coordinate in video frame space (0..videoHeight)
    func sendTouch(action: TouchAction, x: Float, y: Float) {
        guard videoWidth > 0, videoHeight > 0 else { return }

        var data = Data(capacity: 32)

        // Type: INJECT_TOUCH_EVENT = 2
        data.append(2)

        // Action
        data.append(action.rawValue)

        // Pointer ID: SC_POINTER_ID_GENERIC_FINGER = -2 as UInt64
        appendUInt64(&data, UInt64(bitPattern: -2))

        // Position X (int32 big-endian)
        appendInt32(&data, Int32(x))

        // Position Y (int32 big-endian)
        appendInt32(&data, Int32(y))

        // Screen Width (uint16 big-endian)
        appendUInt16(&data, videoWidth)

        // Screen Height (uint16 big-endian)
        appendUInt16(&data, videoHeight)

        // Pressure: 0xFFFF for down/move, 0 for up
        let pressure: UInt16 = (action == .up) ? 0 : 0xFFFF
        appendUInt16(&data, pressure)

        // Action Button: AMOTION_EVENT_BUTTON_PRIMARY = 1 for mouse click
        appendInt32(&data, 1)

        // Buttons: 1 for primary button held
        appendInt32(&data, (action == .up) ? 0 : 1)

        send(data)
    }

    // MARK: - Scroll Events

    func sendScroll(x: Float, y: Float, hScroll: Float, vScroll: Float) {
        guard videoWidth > 0, videoHeight > 0 else { return }

        var data = Data(capacity: 21)

        // Type: INJECT_SCROLL_EVENT = 3
        data.append(3)

        // Position
        appendInt32(&data, Int32(x))
        appendInt32(&data, Int32(y))
        appendUInt16(&data, videoWidth)
        appendUInt16(&data, videoHeight)

        // hScroll and vScroll as i16 fixed-point (range [-1,1] maps to [-32767, 32767])
        // Actual scroll range is [-16, 16], so we divide by 16 first
        let hFixed = Int16(clamping: Int(hScroll / 16.0 * 32767.0))
        let vFixed = Int16(clamping: Int(vScroll / 16.0 * 32767.0))
        appendInt16(&data, hFixed)
        appendInt16(&data, vFixed)

        // Buttons: 0
        appendInt32(&data, 0)

        send(data)
    }

    // MARK: - Key Events

    /// Android key action
    enum KeyAction: UInt8 {
        case down = 0
        case up = 1
    }

    /// Common Android keycodes
    enum AndroidKeycode: Int32 {
        case back = 4
        case home = 3
        case appSwitch = 187
        case volumeUp = 24
        case volumeDown = 25
        case power = 26
    }

    func sendKeycode(action: KeyAction, keycode: AndroidKeycode) {
        var data = Data(capacity: 14)

        // Type: INJECT_KEYCODE = 0
        data.append(0)

        // Action
        data.append(action.rawValue)

        // Keycode (int32 big-endian)
        appendInt32(&data, keycode.rawValue)

        // Repeat (int32)
        appendInt32(&data, 0)

        // MetaState (int32)
        appendInt32(&data, 0)

        send(data)
    }

    func sendBackOrScreenOn(action: KeyAction) {
        var data = Data(capacity: 2)
        // Type: BACK_OR_SCREEN_ON = 4
        data.append(4)
        data.append(action.rawValue)
        send(data)
    }

    // MARK: - Internal (exposed for testing)

    /// Last data packet sent — used by unit tests to verify binary encoding.
    #if DEBUG
    private(set) var lastSentData: Data?
    #endif

    func send(_ data: Data) {
        #if DEBUG
        lastSentData = data
        #endif
        connection?.send(content: data, completion: .contentProcessed { error in
            if let error {
                print("[ControlChannel] Send error: \(error)")
            }
        })
    }

    func appendUInt64(_ data: inout Data, _ value: UInt64) {
        var be = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
    }

    func appendInt32(_ data: inout Data, _ value: Int32) {
        var be = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
    }

    func appendUInt16(_ data: inout Data, _ value: UInt16) {
        var be = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
    }

    func appendInt16(_ data: inout Data, _ value: Int16) {
        var be = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
    }
}
