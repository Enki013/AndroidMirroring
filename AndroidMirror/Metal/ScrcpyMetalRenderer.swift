import Foundation
import MetalKit
import Network

/// Metal renderer that connects to scrcpy-server's raw H.264 stream via a local TCP socket,
/// decodes frames using VideoToolbox, and displays them in a MetalKit view.
@MainActor
final class ScrcpyMetalRenderer: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var statusText = "Waiting for stream…"
    @Published private(set) var latestPixelBuffer: CVPixelBuffer?
    @Published var videoSize: CGSize = CGSize(width: 9, height: 19.5)

    private var streamTask: Task<Void, Never>?
    private let decoder = H264Decoder()
    let controlChannel = ScrcpyControlChannel()
    let audioPlayer = AudioStreamPlayer()
    weak var metalView: MTKView?

    init() {
        decoder.onFrame = { [weak self] buffer in
            Task { @MainActor in
                guard let self else { return }
                self.latestPixelBuffer = buffer

                // Update control channel with video frame dimensions
                let w = UInt16(CVPixelBufferGetWidth(buffer))
                let h = UInt16(CVPixelBufferGetHeight(buffer))
                if self.controlChannel.videoWidth != w || self.controlChannel.videoHeight != h {
                    self.controlChannel.videoWidth = w
                    self.controlChannel.videoHeight = h
                    self.videoSize = CGSize(width: CGFloat(w), height: CGFloat(h))
                    print("[MetalRenderer] Video dimensions: \(w)x\(h)")
                }
            }
        }
    }

    func connect(port: UInt16, audioEnabled: Bool = false, controlEnabled: Bool = true) {
        disconnect()
        isConnected = true
        statusText = "Connecting on port \(port)…"

        streamTask = Task {
            let reader = ScrcpyRawStreamReader(port: port)
            do {
                print("[MetalRenderer] Attempting connection to port \(port)…")
                try await reader.connect()
                print("[MetalRenderer] Connected! Starting NAL unit stream…")
                await MainActor.run { self.statusText = "Receiving video…" }

                // scrcpy expects connections in order: video → audio → control.
                try await Task.sleep(for: .milliseconds(200))

                // 2nd connection: audio (if enabled)
                if audioEnabled {
                    do {
                        try await audioPlayer.connect(port: port)
                        print("[MetalRenderer] Audio player connected")
                    } catch {
                        print("[MetalRenderer] Audio connection failed (device may not support it): \(error)")
                        // Non-fatal — continue without audio
                    }
                    try await Task.sleep(for: .milliseconds(200))
                }

                // 3rd connection (or 2nd if no audio): control
                // Disabled in camera mode — touch events are meaningless for camera source.
                if controlEnabled {
                    controlChannel.connect(port: port)
                    print("[MetalRenderer] Control channel connecting…")
                } else {
                    print("[MetalRenderer] Control channel skipped (camera mode)")
                }

                var nalCount = 0
                for try await nalUnit in reader.nalUnits() {
                    if Task.isCancelled { break }
                    nalCount += 1
                    if nalCount <= 5 || nalCount % 100 == 0 {
                        let nalType = nalUnit.isEmpty ? 0 : nalUnit[0] & 0x1F
                        print("[MetalRenderer] NAL #\(nalCount): type=\(nalType) size=\(nalUnit.count)")
                    }
                    decoder.decode(nalUnit: nalUnit)
                }
                print("[MetalRenderer] NAL stream ended after \(nalCount) units")
            } catch {
                print("[MetalRenderer] Stream error: \(error)")
                await MainActor.run {
                    self.statusText = "Stream error: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                if self.isConnected {
                    self.isConnected = false
                    if self.statusText.hasPrefix("Receiving") {
                        self.statusText = "Stream ended"
                    }
                }
            }
        }
    }

    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        decoder.invalidate()
        audioPlayer.disconnect()
        controlChannel.disconnect()
        isConnected = false
        latestPixelBuffer = nil
        statusText = "Disconnected"
    }
}

// MARK: - Raw H.264 Stream Reader

/// Reads raw H.264 Annex B stream from scrcpy-server (launched with `raw_stream=true`).
/// The stream contains no framing headers — just raw NAL units separated by start codes.
final class ScrcpyRawStreamReader: @unchecked Sendable {
    let port: UInt16
    private var connection: NWConnection?

    /// Retry connecting up to this many times (server may need time to start listening)
    private let maxRetries = 10
    private let retryDelay: UInt64 = 300_000_000 // 300ms

    init(port: UInt16) {
        self.port = port
    }

    func connect() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ScrcpyStreamError.connectionFailed
        }

        // Retry loop: the server may not be listening yet
        var lastError: Error = ScrcpyStreamError.connectionFailed
        for attempt in 0..<maxRetries {
            if Task.isCancelled { throw CancellationError() }

            do {
                try await attemptConnect(to: nwPort)
                return // Success
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: retryDelay)
                }
            }
        }
        throw lastError
    }

    private func attemptConnect(to nwPort: NWEndpoint.Port) async throws {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)

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

        self.connection = conn
    }

    /// Produces an async stream of H.264 NAL units parsed from the raw Annex B byte stream.
    /// NAL units are separated by start codes: 00 00 00 01 or 00 00 01.
    func nalUnits() -> AsyncThrowingStream<Data, Error> {
        guard let connection else {
            return AsyncThrowingStream { $0.finish(throwing: ScrcpyStreamError.notAvailable) }
        }

        return AsyncThrowingStream { continuation in
            var buffer = Data()
            var totalBytesReceived = 0
            let chunkSize = 65536

            func receiveChunk() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: chunkSize) { data, _, isComplete, error in
                    if let error {
                        print("[StreamReader] Error: \(error)")
                        continuation.finish(throwing: error)
                        return
                    }

                    guard let data, !data.isEmpty else {
                        print("[StreamReader] No data received. isComplete=\(isComplete), totalBytes=\(totalBytesReceived), bufferSize=\(buffer.count)")
                        if isComplete {
                            // Flush remaining buffer as final NAL
                            if let lastNAL = Self.extractLastNAL(from: &buffer), !lastNAL.isEmpty {
                                continuation.yield(lastNAL)
                            }
                            continuation.finish()
                        } else {
                            continuation.finish(throwing: ScrcpyStreamError.notAvailable)
                        }
                        return
                    }

                    totalBytesReceived += data.count
                    buffer.append(data)

                    // Extract complete NAL units from buffer
                    while let nalUnit = Self.extractNextNAL(from: &buffer) {
                        if !nalUnit.isEmpty {
                            continuation.yield(nalUnit)
                        }
                    }

                    receiveChunk()
                }
            }

            continuation.onTermination = { _ in
                connection.cancel()
            }

            receiveChunk()
        }
    }

    /// Finds the next complete NAL unit in the buffer (between two start codes).
    /// Removes the consumed bytes from the buffer.
    /// Returns nil if there isn't a complete NAL unit yet.
    static func extractNextNAL(from buffer: inout Data) -> Data? {
        let bytes = [UInt8](buffer)
        guard bytes.count > 4 else { return nil }

        // Find first start code
        guard let firstStart = findStartCode(in: bytes, from: 0) else { return nil }

        // Find second start code after the first one
        let searchFrom = firstStart.offset + firstStart.length
        guard let secondStart = findStartCode(in: bytes, from: searchFrom) else {
            return nil // Need more data
        }

        // Extract NAL unit (bytes between the two start codes)
        let nalStart = firstStart.offset + firstStart.length
        let nalEnd = secondStart.offset
        let nalData = Data(bytes[nalStart..<nalEnd])

        // Remove consumed data up to second start code
        buffer = Data(bytes[secondStart.offset...])

        return nalData
    }

    /// Extracts the last NAL unit from the buffer (when stream ends).
    static func extractLastNAL(from buffer: inout Data) -> Data? {
        let bytes = [UInt8](buffer)
        guard let firstStart = findStartCode(in: bytes, from: 0) else { return nil }
        let nalStart = firstStart.offset + firstStart.length
        guard nalStart < bytes.count else { return nil }
        let nalData = Data(bytes[nalStart...])
        buffer.removeAll()
        return nalData
    }

    /// Finds a start code (00 00 00 01 or 00 00 01) starting from the given offset.
    static func findStartCode(in bytes: [UInt8], from offset: Int) -> (offset: Int, length: Int)? {
        var i = offset
        while i + 2 < bytes.count {
            if bytes[i] == 0 && bytes[i + 1] == 0 {
                // Check 4-byte start code first
                if i + 3 < bytes.count && bytes[i + 2] == 0 && bytes[i + 3] == 1 {
                    return (offset: i, length: 4)
                }
                // Check 3-byte start code
                if bytes[i + 2] == 1 {
                    return (offset: i, length: 3)
                }
            }
            i += 1
        }
        return nil
    }
}

enum ScrcpyStreamError: LocalizedError {
    case notAvailable
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Video stream ended or not available."
        case .connectionFailed:
            return "Could not connect to scrcpy video port."
        }
    }
}
