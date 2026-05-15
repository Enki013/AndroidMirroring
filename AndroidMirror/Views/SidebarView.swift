import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var deviceList: DeviceListViewModel
    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var fileTransfer: FileTransferService
    @Binding var showConnectionSheet: Bool

    var body: some View {
        List(selection: $deviceList.selectedDevice) {
            Section("Devices") {
                if deviceList.isLoading && deviceList.devices.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if deviceList.devices.isEmpty {
                    ContentUnavailableView(
                        "No devices",
                        systemImage: "cable.connector",
                        description: Text("Connect your Android phone via USB or pair wirelessly.")
                    )
                } else {
                    ForEach(deviceList.devices) { device in
                        DeviceRow(device: device)
                            .tag(device)
                    }
                }
            }

            if let device = deviceList.selectedDevice, device.isReady {
                Section("Quick actions") {
                    Button("Start mirroring") {
                        NotificationCenter.default.post(name: .startMirroring, object: nil)
                    }
                    .disabled(mirrorSession.isMirroring)

                    Button("Send files…") {
                        openFilePicker(for: device)
                    }

                    if !fileTransfer.transfers.isEmpty {
                        ForEach(fileTransfer.transfers) { item in
                            TransferRow(item: item)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Android Mirror")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Refresh") {
                    Task { await deviceList.refresh() }
                }
                Spacer()
                Button("Wireless…") {
                    showConnectionSheet = true
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .fileDropOverlay(device: deviceList.selectedDevice)
    }

    private func openFilePicker(for device: AndroidDevice) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            Task {
                await fileTransfer.transfer(urls: panel.urls, to: device)
            }
        }
    }
}

struct DeviceRow: View {
    let device: AndroidDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.transport == .wifi ? "wifi" : "cable.connector")
                .foregroundStyle(device.isReady ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)
                Text(device.serial)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(device.state.label)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(device.isReady ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}

struct TransferRow: View {
    let item: FileTransferItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.url.lastPathComponent)
                .lineLimit(1)
            ProgressView(value: item.progress)
            if let error = item.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }
}

extension Notification.Name {
    static let startMirroring = Notification.Name("AndroidMirror.startMirroring")
}
