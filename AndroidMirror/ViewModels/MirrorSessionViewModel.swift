import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class MirrorSessionViewModel: ObservableObject {
    @Published var isMirroring = false
    @Published var isRecording = false
    @Published var statusMessage: String?

    let scrcpyService = ScrcpyProcessService()
    let serverBridge = ScrcpyServerBridge()
    let metalRenderer = ScrcpyMetalRenderer()

    private let settings = AppSettings.shared
    private var geometry: MirrorWindowGeometry?
    private var bridgeObserver: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    var mirrorOptions: MirrorOptions {
        get { settings.mirrorOptions }
        set { settings.mirrorOptions = newValue }
    }

    func startMirroring(device: AndroidDevice, frame: CGRect) {
        guard device.isReady else {
            statusMessage = "Device not ready."
            return
        }

        scrcpyService.stop()
        statusMessage = "Starting mirror…"
        isMirroring = true

        // Start the server bridge (async: pushes server, creates forward, starts process)
        serverBridge.start(serial: device.serial, options: mirrorOptions)

        // Observe videoPort — when it becomes available, connect the Metal renderer
        bridgeObserver = serverBridge.$videoPort
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] port in
                guard let self else { return }
                self.metalRenderer.connect(port: port)
                self.statusMessage = "Mirror active"
            }

        // Also observe errors
        serverBridge.$lastError
            .compactMap { $0 }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self else { return }
                self.statusMessage = error
                self.isMirroring = false
            }
            .store(in: &cancellables)
    }


    func updateMirrorFrame(_ frame: CGRect) {
        // Resizing is handled natively by the MetalVideoView in embedded mode.
    }

    func stopMirroring() {
        bridgeObserver = nil
        cancellables.removeAll()
        scrcpyService.stop()
        serverBridge.stop()
        metalRenderer.disconnect()
        isMirroring = false
        isRecording = false
        statusMessage = nil
    }

    func restartIfNeeded(device: AndroidDevice?, frame: CGRect) {
        guard isMirroring, let device else { return }
        stopMirroring()
        startMirroring(device: device, frame: frame)
    }

    func startRecording() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "AndroidMirror-\(ISO8601DateFormatter().string(from: Date())).mp4"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.scrcpyService.toggleRecording(to: url)
                self?.isRecording = true
                self?.statusMessage = "Recording to \(url.lastPathComponent)"
            }
        }
    }

    func takeScreenshot(device: AndroidDevice) async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "screenshot.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let pngData = try await AdbService.shared.shell("screencap -p | base64", serial: device.serial)
            if let data = Data(base64Encoded: pngData.replacingOccurrences(of: "\n", with: "")) {
                try data.write(to: url)
                statusMessage = "Screenshot saved."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
