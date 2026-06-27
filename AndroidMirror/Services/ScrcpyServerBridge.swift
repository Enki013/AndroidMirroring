import Foundation

/// Launches scrcpy-server directly on the Android device via ADB and exposes a local
/// TCP port for reading the raw H.264 video stream.
///
/// Protocol (scrcpy 4.0, standalone server with `raw_stream=true`):
///   1. Push scrcpy-server.jar to device
///   2. Create adb forward: tcp:<localPort> → localabstract:scrcpy_<SCID>
///   3. Start server via app_process with key=value parameters
///   4. Client connects to localhost:<localPort> → gets raw H.264 Annex B stream
@MainActor
final class ScrcpyServerBridge: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var videoPort: UInt16?
    @Published private(set) var lastError: String?

    private var serverProcess: Process?
    private var scid: UInt32 = 0
    private var forwardedPort: UInt16 = 0
    private var deviceSerial: String?

    private let locator = BinaryLocator.shared

    /// Server version must match the scrcpy-server binary exactly.
    private let serverVersion = "4.0"

    func start(serial: String, options: MirrorOptions) {
        stop()
        deviceSerial = serial
        scid = UInt32.random(in: 1...0x7FFFFFFF) // 31-bit random SCID

        Task {
            do {
                // Step 1: Push scrcpy-server.jar to device
                try await pushServer(serial: serial)

                // Step 2: Find a free local port and create adb forward
                let localPort = try findFreePort()
                try await createForward(serial: serial, localPort: localPort)
                forwardedPort = localPort

                // Step 3: Start the server process on device
                try startServerProcess(serial: serial, options: options)

                // Give adb forward enough time to attach to the device-side local socket.
                // If the desktop connects too early, adb accepts the TCP connection but the
                // remote localabstract socket is not ready yet; the first video socket then
                // closes with 0 bytes, leaving the mirror stuck on the grey placeholder.
                try await Task.sleep(for: .milliseconds(1000))

                await MainActor.run {
                    self.videoPort = localPort
                    self.isActive = true
                    self.lastError = nil
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isActive = false
                }
            }
        }
    }

    func stop() {
        if let serverProcess, serverProcess.isRunning {
            serverProcess.terminate()
        }
        serverProcess = nil

        // Remove adb forward
        if forwardedPort > 0, let serial = deviceSerial {
            let localPort = forwardedPort
            Task {
                try? await removeForward(serial: serial, localPort: localPort)
            }
        }

        isActive = false
        videoPort = nil
        forwardedPort = 0
    }

    // MARK: - Private

    private func pushServer(serial: String) async throws {
        guard let serverJarURL = try? locator.url(for: "scrcpy-server") else {
            throw ScrcpyServerError.serverBinaryNotFound
        }

        let result = try await ProcessRunner.run(
            executable: try locator.url(for: "adb"),
            arguments: ["-s", serial, "push", serverJarURL.path, "/data/local/tmp/scrcpy-server.jar"],
            environment: locator.environment()
        )

        guard result.succeeded else {
            throw ScrcpyServerError.pushFailed(result.stderr)
        }
    }

    private func createForward(serial: String, localPort: UInt16) async throws {
        let socketName = "scrcpy_\(String(format: "%08x", scid))"
        let result = try await ProcessRunner.run(
            executable: try locator.url(for: "adb"),
            arguments: ["-s", serial, "forward", "tcp:\(localPort)", "localabstract:\(socketName)"],
            environment: locator.environment()
        )

        guard result.succeeded else {
            throw ScrcpyServerError.forwardFailed(result.stderr)
        }
    }

    private func removeForward(serial: String, localPort: UInt16) async throws {
        _ = try await ProcessRunner.run(
            executable: try locator.url(for: "adb"),
            arguments: ["-s", serial, "forward", "--remove", "tcp:\(localPort)"],
            environment: locator.environment()
        )
    }

    private func startServerProcess(serial: String, options: MirrorOptions) throws {
        let adbURL = try locator.url(for: "adb")

        // Build server command arguments
        let serverArgs = options.serverArguments(scid: scid)
        let serverCommand = "CLASSPATH=/data/local/tmp/scrcpy-server.jar app_process / com.genymobile.scrcpy.Server \(serverVersion) \(serverArgs.joined(separator: " "))"

        print("[ScrcpyServerBridge] Starting server: adb -s \(serial) shell \(serverCommand)")

        let process = Process()
        process.executableURL = adbURL
        process.arguments = ["-s", serial, "shell", serverCommand]
        process.environment = locator.environment()

        // adb shell merges remote stdout+stderr into adb's stdout.
        // We MUST read it to see server logs and prevent pipe buffer deadlock.
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        // Read stdout asynchronously for debug logging (contains scrcpy-server output)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                    print("[ScrcpyServer] \(line)")
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                guard let self, self.serverProcess === proc else { return }
                print("[ScrcpyServerBridge] Server process terminated with status \(proc.terminationStatus)")

                if proc.terminationStatus != 0 && self.isActive {
                    self.lastError = "Server terminated unexpectedly (exit code \(proc.terminationStatus))"
                }

                self.isActive = false
                self.serverProcess = nil
            }
        }

        try process.run()
        self.serverProcess = process
    }

    private func findFreePort() throws -> UInt16 {
        // Bind to port 0 to get a free port from the OS
        let socketFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketFD >= 0 else {
            throw ScrcpyServerError.noFreePort
        }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0 // Let OS pick
        addr.sin_addr.s_addr = INADDR_ANY // 0 — byte-order safe

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(socketFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw ScrcpyServerError.noFreePort
        }

        var nameLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let gsnResult = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(socketFD, sockPtr, &nameLen)
            }
        }
        guard gsnResult == 0 else {
            throw ScrcpyServerError.noFreePort
        }

        let port = UInt16(bigEndian: addr.sin_port)
        guard port > 0 else {
            throw ScrcpyServerError.noFreePort
        }
        return port
    }
}

enum ScrcpyServerError: LocalizedError {
    case serverBinaryNotFound
    case pushFailed(String)
    case forwardFailed(String)
    case noFreePort
    case serverStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverBinaryNotFound:
            return "scrcpy-server binary not found in app bundle."
        case .pushFailed(let msg):
            return "Failed to push scrcpy-server to device: \(msg)"
        case .forwardFailed(let msg):
            return "Failed to create adb forward: \(msg)"
        case .noFreePort:
            return "Could not find a free local TCP port."
        case .serverStartFailed(let msg):
            return "Failed to start scrcpy server: \(msg)"
        }
    }
}
