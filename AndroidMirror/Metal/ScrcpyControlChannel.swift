import AppKit
import Foundation
import Network

/// Handles the scrcpy control socket connection and sends input events to the device.
///
/// Binary protocol reference (scrcpy 4.0):
///   Touch: type(1) + action(1) + pointerId(8) + x(4) + y(4) + screenW(2) + screenH(2) + pressure(2) + actionButton(4) + buttons(4) = 32 bytes
///   Keycode: type(1) + action(1) + keycode(4) + repeat(4) + metaState(4) = 14 bytes
///   Text: type(1) + length(4) + UTF-8 bytes
///   Scroll: type(1) + x(4) + y(4) + screenW(2) + screenH(2) + hScroll(2) + vScroll(2) + buttons(4) = 21 bytes
///   Clipboard: type(1) + sequence(8) + paste(1) + length(4) + UTF-8 bytes
final class ScrcpyControlChannel: @unchecked Sendable {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "scrcpy.control", qos: .userInteractive)
    private var receiveBuffer = Data()

    private static let injectTextMaxLength = 300
    private static let deviceMsgMaxSize = 1 << 18

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

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("[ControlChannel] Connected!")
                self?.receiveDeviceMessages()
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
        receiveBuffer.removeAll()
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
        case dpadUp = 19
        case dpadDown = 20
        case dpadLeft = 21
        case dpadRight = 22
        case appSwitch = 187
        case volumeUp = 24
        case volumeDown = 25
        case power = 26
        case a = 29
        case b = 30
        case c = 31
        case d = 32
        case e = 33
        case f = 34
        case g = 35
        case h = 36
        case i = 37
        case j = 38
        case k = 39
        case l = 40
        case m = 41
        case n = 42
        case o = 43
        case p = 44
        case q = 45
        case r = 46
        case s = 47
        case t = 48
        case u = 49
        case v = 50
        case w = 51
        case x = 52
        case y = 53
        case z = 54
        case tab = 61
        case enter = 66
        case delete = 67
        case escape = 111
        case forwardDelete = 112
        case moveHome = 122
        case moveEnd = 123
        case pageUp = 92
        case pageDown = 93
        case cut = 277
        case copy = 278
        case paste = 279
    }

    struct MetaState: OptionSet {
        let rawValue: Int32

        static let shift = MetaState(rawValue: 0x01)
        static let alt = MetaState(rawValue: 0x02)
        static let control = MetaState(rawValue: 0x1000)
        static let command = MetaState(rawValue: 0x10000)
    }

    enum ClipboardCopyKey: UInt8 {
        case none = 0
        case copy = 1
        case cut = 2
    }

    func sendKeycode(
        action: KeyAction,
        keycode: AndroidKeycode,
        repeatCount: Int32 = 0,
        metaState: MetaState = []
    ) {
        var data = Data(capacity: 14)

        // Type: INJECT_KEYCODE = 0
        data.append(0)

        // Action
        data.append(action.rawValue)

        // Keycode (int32 big-endian)
        appendInt32(&data, keycode.rawValue)

        // Repeat (int32)
        appendInt32(&data, repeatCount)

        // MetaState (int32)
        appendInt32(&data, metaState.rawValue)

        send(data)
    }

    func sendKeyPress(_ keycode: AndroidKeycode, metaState: MetaState = []) {
        sendKeycode(action: .down, keycode: keycode, metaState: metaState)
        sendKeycode(action: .up, keycode: keycode, metaState: metaState)
    }

    func sendText(_ text: String) {
        let payload = utf8Data(for: text, maxLength: Self.injectTextMaxLength)
        guard !payload.isEmpty else { return }

        var data = Data(capacity: 5 + payload.count)
        // Type: INJECT_TEXT = 1
        data.append(1)
        appendUInt32(&data, UInt32(payload.count))
        data.append(payload)
        send(data)
    }

    func sendGetClipboard(copyKey: ClipboardCopyKey) {
        var data = Data(capacity: 2)
        // Type: GET_CLIPBOARD = 8
        data.append(8)
        data.append(copyKey.rawValue)
        send(data)
    }

    func sendSetClipboard(text: String, paste: Bool, sequence: UInt64 = 0) {
        let maxLength = Self.deviceMsgMaxSize - 14
        let payload = utf8Data(for: text, maxLength: maxLength)

        var data = Data(capacity: 14 + payload.count)
        // Type: SET_CLIPBOARD = 9
        data.append(9)
        appendUInt64(&data, sequence)
        data.append(paste ? 1 : 0)
        appendUInt32(&data, UInt32(payload.count))
        data.append(payload)
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

    private func receiveDeviceMessages() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                print("[ControlChannel] Receive error: \(error)")
                return
            }

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processReceiveBuffer()
            }

            if !isComplete {
                self.receiveDeviceMessages()
            }
        }
    }

    private func processReceiveBuffer() {
        while true {
            guard !receiveBuffer.isEmpty else { return }

            switch receiveBuffer[0] {
            case 0:
                guard receiveBuffer.count >= 5 else { return }
                let length = Int(readUInt32(receiveBuffer, at: 1))
                guard length <= Self.deviceMsgMaxSize - 5 else {
                    receiveBuffer.removeAll()
                    return
                }
                guard receiveBuffer.count >= 5 + length else { return }

                let payload = receiveBuffer.subdata(in: 5..<(5 + length))
                if let text = String(data: payload, encoding: .utf8) {
                    syncComputerClipboard(text)
                }
                receiveBuffer.removeSubrange(0..<(5 + length))
            case 1:
                guard receiveBuffer.count >= 9 else { return }
                // ACK_CLIPBOARD. No async paste wait is currently needed.
                receiveBuffer.removeSubrange(0..<9)
            case 2:
                guard receiveBuffer.count >= 5 else { return }
                let size = Int(readUInt16(receiveBuffer, at: 3))
                guard receiveBuffer.count >= 5 + size else { return }
                receiveBuffer.removeSubrange(0..<(5 + size))
            default:
                print("[ControlChannel] Unknown device message type: \(receiveBuffer[0])")
                receiveBuffer.removeAll()
                return
            }
        }
    }

    private func syncComputerClipboard(_ text: String) {
        DispatchQueue.main.async {
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == text {
                return
            }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            print("[ControlChannel] Device clipboard copied")
        }
    }

    private func utf8Data(for text: String, maxLength: Int) -> Data {
        var data = Data(text.utf8)
        guard data.count > maxLength else { return data }

        data = Data(data.prefix(maxLength))
        while !data.isEmpty && String(data: data, encoding: .utf8) == nil {
            data.removeLast()
        }
        return data
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset]) << 24
        let b1 = UInt32(data[offset + 1]) << 16
        let b2 = UInt32(data[offset + 2]) << 8
        let b3 = UInt32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset]) << 8
        let b1 = UInt16(data[offset + 1])
        return b0 | b1
    }

    func appendUInt64(_ data: inout Data, _ value: UInt64) {
        var be = value.bigEndian
        data.append(contentsOf: withUnsafeBytes(of: &be) { Array($0) })
    }

    func appendUInt32(_ data: inout Data, _ value: UInt32) {
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
