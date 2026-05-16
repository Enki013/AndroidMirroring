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


    var mirrorPreset: QualityPreset {
        get { QualityPreset(rawValue: mirrorPresetRaw) ?? .balanced }
        set { mirrorPresetRaw = newValue.rawValue }
    }

    var mirrorOptions: MirrorOptions {
        get {
            MirrorOptions(
                preset: mirrorPreset,
                audioEnabled: mirrorAudioEnabled,
                turnScreenOff: mirrorTurnScreenOff,
                stayAwake: true
            )
        }
        set {
            mirrorPreset = newValue.preset
            mirrorAudioEnabled = newValue.audioEnabled
            mirrorTurnScreenOff = newValue.turnScreenOff
        }
    }
}
