import AppKit
import Foundation
import SwiftUI

@MainActor
final class MirrorSessionViewModel: ObservableObject {
    @Published var isMirroring = false
    @Published var isRecording = false
    @Published var statusMessage: String?
    @Published var useEmbeddedVideo: Bool = false

    let scrcpyService = ScrcpyProcessService()
    let serverBridge = ScrcpyServerBridge()
    let metalRenderer = ScrcpyMetalRenderer()

    private let settings = AppSettings.shared
    private var geometry: MirrorWindowGeometry?

    var mirrorOptions: MirrorOptions {
        get { settings.mirrorOptions }
        set { settings.mirrorOptions = newValue }
    }

    func startMirroring(device: AndroidDevice, frame: CGRect) {
        guard device.isReady else {
            statusMessage = "Device not ready."
            return
        }

        let geom = WindowGeometryConverter.geometry(for: frame)
        geometry = geom
        useEmbeddedVideo = settings.useEmbeddedVideo

        if useEmbeddedVideo {
            scrcpyService.stop()
            serverBridge.start(serial: device.serial, options: mirrorOptions)
            metalRenderer.connect(serial: device.serial, port: serverBridge.videoPort ?? 27183)
            isMirroring = serverBridge.isActive
            statusMessage = isMirroring ? "Embedded mirror active" : serverBridge.lastError
        } else {
            serverBridge.stop()
            metalRenderer.disconnect()
            scrcpyService.start(serial: device.serial, options: mirrorOptions, geometry: geom)
            isMirroring = scrcpyService.isRunning
            statusMessage = isMirroring ? nil : scrcpyService.lastError
        }
    }

    func updateMirrorFrame(_ frame: CGRect) {
        guard isMirroring, !useEmbeddedVideo else { return }
        let geom = WindowGeometryConverter.geometry(for: frame)
        if geom != geometry {
            geometry = geom
            scrcpyService.updateGeometry(geom)
        }
    }

    func stopMirroring() {
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
