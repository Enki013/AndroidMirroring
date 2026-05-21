import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("transferDestination") var transferDestination: String = "/sdcard/Download/"
    @AppStorage("openDownloadsAfterTransfer") var openDownloadsAfterTransfer: Bool = true
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("mirrorPreset") private var mirrorPresetRaw: String = QualityPreset.balanced.rawValue
    @AppStorage("mirrorAudioEnabled") var mirrorAudioEnabled: Bool = true
    @AppStorage("mirrorTurnScreenOff") var mirrorTurnScreenOff: Bool = false
    @AppStorage("mirrorVideoSource") private var mirrorVideoSourceRaw: String = VideoSource.display.rawValue
    @AppStorage("mirrorCameraFacing") private var mirrorCameraFacingRaw: String = CameraFacing.back.rawValue
    @AppStorage("mirrorCameraFps") var mirrorCameraFps: Int = 30


    var mirrorPreset: QualityPreset {
        get { QualityPreset(rawValue: mirrorPresetRaw) ?? .balanced }
        set { mirrorPresetRaw = newValue.rawValue }
    }

    var mirrorVideoSource: VideoSource {
        get { VideoSource(rawValue: mirrorVideoSourceRaw) ?? .display }
        set { mirrorVideoSourceRaw = newValue.rawValue }
    }

    var mirrorCameraFacing: CameraFacing {
        get { CameraFacing(rawValue: mirrorCameraFacingRaw) ?? .back }
        set { mirrorCameraFacingRaw = newValue.rawValue }
    }

    var mirrorOptions: MirrorOptions {
        get {
            MirrorOptions(
                preset: mirrorPreset,
                audioEnabled: mirrorAudioEnabled,
                turnScreenOff: mirrorTurnScreenOff,
                stayAwake: true,
                videoSource: mirrorVideoSource,
                cameraFacing: mirrorCameraFacing,
                cameraFps: mirrorCameraFps
            )
        }
        set {
            mirrorPreset = newValue.preset
            mirrorAudioEnabled = newValue.audioEnabled
            mirrorTurnScreenOff = newValue.turnScreenOff
            mirrorVideoSource = newValue.videoSource
            mirrorCameraFacing = newValue.cameraFacing
            mirrorCameraFps = newValue.cameraFps
        }
    }
}
