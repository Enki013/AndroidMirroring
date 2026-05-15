import SwiftUI

struct MirrorView: View {
    @EnvironmentObject private var deviceList: DeviceListViewModel
    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var settings: AppSettings

    @State private var mirrorFrame: CGRect = .zero

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(red: 0.08, green: 0.08, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let device = deviceList.selectedDevice, device.isReady {
                activeMirror(device: device)
            } else {
                emptyState
            }
        }
        .toolbar {
            MirrorToolbar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startMirroring)) { _ in
            startMirror()
        }
    }

    private func activeMirror(device: AndroidDevice) -> some View {
        VStack(spacing: 16) {
            MirrorControlBar(device: device, mirrorFrame: mirrorFrame)

            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)

                ZStack {
                    DeviceChrome {
                        if mirrorSession.useEmbeddedVideo && mirrorSession.isMirroring {
                            MetalVideoView(renderer: mirrorSession.metalRenderer)
                        } else if mirrorSession.isMirroring {
                            // scrcpy SDL window is positioned behind this transparent area
                            Color.clear
                                .overlay {
                                    Text("Mirroring active")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .opacity(0.6)
                                }
                        } else {
                            placeholder(device: device)
                        }
                    }
                    .fileDropOverlay(device: device)
                }
                .onAppear { mirrorFrame = frame }
                .onChange(of: frame) { _, newFrame in
                    mirrorFrame = newFrame
                    mirrorSession.updateMirrorFrame(newFrame)
                }
            }
            .padding(24)

            if let message = mirrorSession.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func placeholder(device: AndroidDevice) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "smartphone")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(device.displayName)
                .font(.title3.weight(.medium))
            Button("Start mirroring") {
                startMirror()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Connect a device",
            systemImage: "iphone.and.arrow.forward",
            description: Text("Plug in your Android phone with USB debugging enabled, or pair wirelessly from the sidebar.")
        )
    }

    private func startMirror() {
        guard let device = deviceList.selectedDevice, device.isReady else { return }
        guard mirrorFrame != .zero else { return }
        mirrorSession.startMirroring(device: device, frame: mirrorFrame)
    }
}

struct DeviceChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: 420)
            .aspectRatio(9 / 19.5, contentMode: .fit)
            .background(Color(white: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 32, y: 16)
    }
}

struct MirrorControlBar: View {
    let device: AndroidDevice
    let mirrorFrame: CGRect

    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            Picker("Quality", selection: Binding(
                get: { settings.mirrorPreset },
                set: { newValue in
                    settings.mirrorPreset = newValue
                    mirrorSession.restartIfNeeded(device: device, frame: mirrorFrame)
                }
            )) {
                ForEach(QualityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            Toggle("Audio", isOn: Binding(
                get: { settings.mirrorAudioEnabled },
                set: {
                    settings.mirrorAudioEnabled = $0
                    mirrorSession.restartIfNeeded(device: device, frame: mirrorFrame)
                }
            ))

            Toggle("Embedded", isOn: Binding(
                get: { settings.useEmbeddedVideo },
                set: {
                    settings.useEmbeddedVideo = $0
                    mirrorSession.restartIfNeeded(device: device, frame: mirrorFrame)
                }
            ))
            .help("Phase 2: Metal embedded video (experimental)")

            Spacer()

            if mirrorSession.isMirroring {
                Button {
                    Task { await mirrorSession.takeScreenshot(device: device) }
                } label: {
                    Label("Screenshot", systemImage: "camera")
                }

                Button {
                    mirrorSession.startRecording()
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
            }
        }
        .padding(.horizontal, 24)
    }
}

struct MirrorToolbar: ToolbarContent {
    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var deviceList: DeviceListViewModel

    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            if mirrorSession.isMirroring {
                Text("Live")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}
