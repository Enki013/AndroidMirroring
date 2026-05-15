import AppKit
import Foundation

struct MirrorWindowGeometry: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

@MainActor
final class ScrcpyProcessService: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published var windowTitle: String = "AndroidMirror-\(UUID().uuidString)"

    private var process: Process?
    private var geometry: MirrorWindowGeometry?
    private var deviceSerial: String?
    private var options: MirrorOptions = .init()

    func start(serial: String, options: MirrorOptions, geometry: MirrorWindowGeometry) {
        stop()
        self.deviceSerial = serial
        self.options = options
        self.geometry = geometry
        windowTitle = "AndroidMirror-\(serial.prefix(8))"

        guard let scrcpyURL = try? BinaryLocator.shared.url(for: "scrcpy") else {
            lastError = "scrcpy binary not found in app bundle."
            return
        }

        var args = options.scrcpyArguments(serial: serial)
        args += windowArguments(for: geometry)

        let process = Process()
        process.executableURL = scrcpyURL
        process.arguments = args
        process.environment = BinaryLocator.shared.environment()

        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        process.terminationHandler = { [weak self] proc in
            Task { @MainActor in
                guard let self else { return }
                if self.process === proc {
                    self.isRunning = false
                    self.process = nil
                }
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isRunning = false
        }
    }

    func updateGeometry(_ geometry: MirrorWindowGeometry) {
        guard isRunning else { return }
        guard let serial = deviceSerial else { return }

        // scrcpy does not support live window moves; restart with new geometry
        start(serial: serial, options: options, geometry: geometry)
    }

    func stop() {
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        isRunning = false
    }

    func toggleRecording(to url: URL) {
        // Recording is started via fresh scrcpy invocation with --record
        guard let serial = deviceSerial else { return }
        guard let scrcpyURL = try? BinaryLocator.shared.url(for: "scrcpy") else { return }

        var args = options.scrcpyArguments(serial: serial)
        args += ["--record=\(url.path)"]
        args += windowArguments(for: geometry ?? MirrorWindowGeometry(x: 100, y: 100, width: 400, height: 800))

        let recordProcess = Process()
        recordProcess.executableURL = scrcpyURL
        recordProcess.arguments = args
        recordProcess.environment = BinaryLocator.shared.environment()
        try? recordProcess.run()
    }

    private func windowArguments(for geometry: MirrorWindowGeometry) -> [String] {
        [
            "--window-title=\(windowTitle)",
            "--window-borderless",
            "--window-x=\(geometry.x)",
            "--window-y=\(geometry.y)",
            "--window-width=\(geometry.width)",
            "--window-height=\(geometry.height)",
            "--disable-screensaver",
            "--background-color=1a1a1e"
        ]
    }
}

/// Converts SwiftUI/global coordinates to screen coordinates for scrcpy SDL window placement.
enum WindowGeometryConverter {
    static func geometry(for frame: CGRect, in screen: NSScreen? = NSScreen.main) -> MirrorWindowGeometry {
        guard let screen else {
            return MirrorWindowGeometry(
                x: Int(frame.origin.x),
                y: Int(frame.origin.y),
                width: Int(frame.width),
                height: Int(frame.height)
            )
        }

        // scrcpy/SDL uses top-left origin; convert from bottom-left Cocoa coords
        let screenHeight = screen.frame.height
        let screenOrigin = screen.frame.origin
        let globalX = frame.origin.x + screenOrigin.x
        let globalY = screenOrigin.y + screenHeight - frame.origin.y - frame.height

        return MirrorWindowGeometry(
            x: Int(globalX),
            y: Int(globalY),
            width: max(320, Int(frame.width)),
            height: max(480, Int(frame.height))
        )
    }
}
