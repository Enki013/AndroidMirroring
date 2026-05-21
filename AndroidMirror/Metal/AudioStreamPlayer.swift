import AVFoundation
import Foundation
import Network

/// Connects to the scrcpy-server audio socket, reads raw PCM bytes
/// (`audio_codec=raw`, `raw_stream=true`), and plays them through `AVAudioEngine`.
///
/// PCM format from Android's AudioRecord: 48 kHz, 16-bit signed LE, stereo (interleaved).
@MainActor
final class AudioStreamPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

    // MARK: - Engine

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    /// Output format: Float32, non-interleaved (AVAudioEngine standard).
    private let playbackFormat: AVAudioFormat = {
        AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    }()

    // MARK: - Network

    private var connection: NWConnection?
    private var readTask: Task<Void, Never>?

    /// Retry settings — the server may not be ready instantly.
    private let maxRetries = 8
    private let retryDelay: Duration = .milliseconds(300)

    // MARK: - Public

    /// Connect to the audio socket on `port`.  Must be called **after** the video
    /// connection and **before** the control connection (scrcpy connection order).
    func connect(port: UInt16) async throws {
        disconnect()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AudioPlayerError.connectionFailed
        }

        // Retry loop — server may not accept audio connection immediately.
        var lastError: Error = AudioPlayerError.connectionFailed
        for attempt in 0..<maxRetries {
            if Task.isCancelled { throw CancellationError() }
            do {
                try await attemptConnect(to: nwPort)
                print("[AudioPlayer] Connected on attempt \(attempt + 1)")
                startEngine()
                startReading()
                return
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    try await Task.sleep(for: retryDelay)
                }
            }
        }
        throw lastError
    }

    func disconnect() {
        readTask?.cancel()
        readTask = nil

        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil

        connection?.cancel()
        connection = nil

        isPlaying = false
    }

    // MARK: - Private — Connection

    private func attemptConnect(to nwPort: NWEndpoint.Port) async throws {
        let conn = NWConnection(
            to: .hostPort(host: .ipv4(.loopback), port: nwPort),
            using: .tcp
        )

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let error):
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: error)
                case .cancelled:
                    conn.stateUpdateHandler = nil
                    cont.resume(throwing: AudioPlayerError.connectionFailed)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        self.connection = conn
    }

    // MARK: - Private — Audio Engine

    private func startEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        do {
            try engine.start()
            player.play()
            self.audioEngine = engine
            self.playerNode = player
            self.isPlaying = true
            print("[AudioPlayer] AVAudioEngine started (48 kHz Float32 stereo)")
        } catch {
            print("[AudioPlayer] AVAudioEngine failed to start: \(error)")
        }
    }

    // MARK: - Private — Stream Reading

    private func startReading() {
        guard let connection else { return }

        readTask = Task.detached { [weak self] in
            let chunkSize = 8192 // bytes per read (~42 ms of audio at 48 kHz stereo s16le)

            while !Task.isCancelled {
                do {
                    let data: Data = try await withCheckedThrowingContinuation { cont in
                        connection.receive(
                            minimumIncompleteLength: 1,
                            maximumLength: chunkSize
                        ) { data, _, isComplete, error in
                            if let error {
                                cont.resume(throwing: error)
                            } else if let data, !data.isEmpty {
                                cont.resume(returning: data)
                            } else if isComplete {
                                cont.resume(throwing: AudioPlayerError.streamEnded)
                            } else {
                                cont.resume(throwing: AudioPlayerError.streamEnded)
                            }
                        }
                    }

                    await self?.scheduleAudioBuffer(data: data)
                } catch {
                    if !Task.isCancelled {
                        print("[AudioPlayer] Read error: \(error)")
                    }
                    break
                }
            }

            await MainActor.run {
                self?.isPlaying = false
            }
        }
    }

    /// Converts raw s16le interleaved PCM to Float32 non-interleaved and schedules on the player node.
    func scheduleAudioBuffer(data: Data) {
        guard let playerNode else { return }

        // Each frame = 2 channels × 2 bytes = 4 bytes
        let frameCount = data.count / 4
        guard frameCount > 0 else { return }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat,
                                            frameCapacity: AVAudioFrameCount(frameCount)) else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        // De-interleave and convert s16le → Float32
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let left  = buffer.floatChannelData![0]
            let right = buffer.floatChannelData![1]

            for i in 0..<frameCount {
                left[i]  = Float(samples[i * 2])     / 32768.0
                right[i] = Float(samples[i * 2 + 1]) / 32768.0
            }
        }

        playerNode.scheduleBuffer(buffer)
    }
}

// MARK: - Errors

enum AudioPlayerError: LocalizedError {
    case connectionFailed
    case streamEnded

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Could not connect to scrcpy audio socket."
        case .streamEnded:
            return "Audio stream ended."
        }
    }
}
