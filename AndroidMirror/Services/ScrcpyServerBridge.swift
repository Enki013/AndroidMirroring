import Foundation

/// Phase 2: launches scrcpy in no-window mode and exposes the video socket port for Metal decoding.
@MainActor
final class ScrcpyServerBridge: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var videoPort: UInt16?
    @Published private(set) var lastError: String?

    private var process: Process?

    func start(serial: String, options: MirrorOptions) {
        stop()

        guard let scrcpyURL = try? BinaryLocator.shared.url(for: "scrcpy") else {
            lastError = "scrcpy binary not found."
            return
        }

        // Port 0 lets scrcpy pick a free port; we parse stderr for the actual port when available.
        // Fallback: use default forward and connect via adb.
        var args = options.scrcpyArguments(serial: serial)
        args += ["--no-window", "--no-audio-playback", "--video-buffer=0"]

        let process = Process()
        process.executableURL = scrcpyURL
        process.arguments = args
        process.environment = BinaryLocator.shared.environment()

        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self, self.process === proc else { return }
                self.isActive = false
                self.process = nil
            }
        }

        do {
            try process.run()
            self.process = process
            isActive = true
            videoPort = 27183
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        isActive = false
        videoPort = nil
    }
}
