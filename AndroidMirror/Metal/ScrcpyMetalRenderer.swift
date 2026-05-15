import Foundation
import MetalKit
import Network

/// Phase 2: Metal renderer with VideoToolbox H.264 decoder for embedded scrcpy stream.
@MainActor
final class ScrcpyMetalRenderer: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "Waiting for stream…"
    @Published private(set) var latestPixelBuffer: CVPixelBuffer?

    private var streamTask: Task<Void, Never>?
    private let decoder = H264Decoder()
    weak var metalView: MTKView?

    init() {
        decoder.onFrame = { [weak self] buffer in
            Task { @MainActor in
                guard let self else { return }
                self.latestPixelBuffer = buffer
                self.metalView?.needsDisplay = true
            }
        }
    }

    func connect(serial: String, port: UInt16) {
        disconnect()
        isConnected = true
        statusText = "Connecting to \(serial) on port \(port)…"

        streamTask = Task {
            let socket = ScrcpyVideoSocket(port: port)
            do {
                try await socket.connect()
                await MainActor.run { self.statusText = "Receiving video…" }
                for try await packet in socket.packets() {
                    if Task.isCancelled { break }
                    decoder.decode(nalUnit: packet)
                }
            } catch {
                await MainActor.run {
                    self.statusText = "Embedded stream unavailable — use windowed mode. (\(error.localizedDescription))"
                }
            }
        }
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        decoder.invalidate()
        isConnected = false
        latestPixelBuffer = nil
        statusText = "Disconnected"
    }
}

enum ScrcpyStreamError: LocalizedError {
    case notAvailable
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Video socket not available. Use windowed mirroring or ensure scrcpy is running."
        case .connectionFailed:
            return "Could not connect to scrcpy video port."
        }
    }
}

/// Reads length-prefixed packets from scrcpy video socket (default port 27183).
final class ScrcpyVideoSocket: @unchecked Sendable {
    let port: UInt16
    private var connection: NWConnection?

    init(port: UInt16) {
        self.port = port
    }

    func connect() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ScrcpyStreamError.connectionFailed
        }
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)
        connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    continuation.resume(throwing: ScrcpyStreamError.connectionFailed)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }
    }

    func packets() -> AsyncThrowingStream<Data, Error> {
        guard let connection else {
            return AsyncThrowingStream { $0.finish(throwing: ScrcpyStreamError.notAvailable) }
        }

        return AsyncThrowingStream { continuation in
            func receiveHeader() {
                connection.receive(minimumIncompleteLength: 12, maximumLength: 12) { data, _, _, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let data, data.count >= 12 else {
                        continuation.finish()
                        return
                    }
                    let length = data.withUnsafeBytes { ptr -> UInt32 in
                        ptr.load(fromByteOffset: 8, as: UInt32.self).bigEndian
                    }
                    receivePayload(Int(length))
                }
            }

            func receivePayload(_ length: Int) {
                guard length > 0, length < 10_000_000 else {
                    continuation.finish(throwing: ScrcpyStreamError.notAvailable)
                    return
                }
                connection.receive(minimumIncompleteLength: length, maximumLength: length) { data, _, _, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    if let data {
                        continuation.yield(data)
                    }
                    receiveHeader()
                }
            }

            receiveHeader()
        }
    }
}
