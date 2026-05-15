import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("File transfer") {
                TextField("Destination on device", text: $settings.transferDestination)
                Toggle("Open Downloads after transfer", isOn: $settings.openDownloadsAfterTransfer)
            }

            Section("Mirroring defaults") {
                Picker("Quality preset", selection: Binding(
                    get: { settings.mirrorPreset },
                    set: { settings.mirrorPreset = $0 }
                )) {
                    ForEach(QualityPreset.allCases) { preset in
                        VStack(alignment: .leading) {
                            Text(preset.title)
                            Text(preset.subtitle).font(.caption)
                        }
                        .tag(preset)
                    }
                }
                Toggle("Forward audio", isOn: $settings.mirrorAudioEnabled)
                Toggle("Turn device screen off while mirroring", isOn: $settings.mirrorTurnScreenOff)
                Toggle("Use embedded Metal video (experimental)", isOn: $settings.useEmbeddedVideo)
            }

            Section("Shortcuts (scrcpy)") {
                LabeledContent("Back", value: "Right-click")
                LabeledContent("Home", value: "Middle-click")
                LabeledContent("Fullscreen", value: "⌘F")
                LabeledContent("Rotate", value: "⌘R")
                LabeledContent("Paste", value: "⌘V")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
        .padding()
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Welcome to Android Mirror")
                .font(.largeTitle.weight(.semibold))

            VStack(alignment: .leading, spacing: 12) {
                onboardingRow("1", "Enable Developer options and USB debugging on your Android device.")
                onboardingRow("2", "Connect via USB or pair wirelessly from the sidebar.")
                onboardingRow("3", "Drag files onto the mirror to send them to Downloads.")
                onboardingRow("!", "Xiaomi users: enable USB debugging (Security Settings) and reboot.")
            }
            .frame(maxWidth: 420)

            if !BinaryLocator.shared.binariesAvailable {
                Text("Bundled scrcpy/adb binaries not found. Run scripts/fetch-binaries.sh before building.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button("Get started") {
                settings.hasCompletedOnboarding = true
                isPresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 520, height: 480)
    }

    private func onboardingRow(_ badge: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(badge)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.accentColor.opacity(0.2))
                .clipShape(Circle())
            Text(text)
                .font(.body)
        }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)

            Text("Android Mirror")
                .font(.title.weight(.semibold))
            Text("Powered by scrcpy (Apache-2.0)")
                .foregroundStyle(.secondary)

            Link("scrcpy on GitHub", destination: URL(string: "https://github.com/Genymobile/scrcpy")!)
        }
        .padding(32)
        .frame(width: 320)
    }
}
