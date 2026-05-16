import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var deviceList: DeviceListViewModel
    @EnvironmentObject private var mirrorSession: MirrorSessionViewModel
    @EnvironmentObject private var fileTransfer: FileTransferService

    @State private var showConnectionSheet = false
    @State private var showOnboarding = false

    var body: some View {
        mainLayout
        .onAppear {
            if !settings.hasCompletedOnboarding {
                showOnboarding = true
            }
            deviceList.startPolling()
        }
        .onDisappear {
            deviceList.stopPolling()
            mirrorSession.stopMirroring()
        }
        .sheet(isPresented: $showConnectionSheet) {
            ConnectionSheet()
                .environmentObject(deviceList)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
    }

    private var mainLayout: some View {
        MirrorView()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if mirrorSession.isMirroring {
                    Button {
                        mirrorSession.stopMirroring()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }

                Menu {
                    if deviceList.isLoading && deviceList.devices.isEmpty {
                        Text("Searching...")
                    } else if deviceList.devices.isEmpty {
                        Text("No Devices")
                    } else {
                        Picker("Device", selection: $deviceList.selectedDevice) {
                            ForEach(deviceList.devices) { device in
                                Text(device.displayName).tag(Optional(device))
                            }
                        }
                    }

                    Divider()

                    if let device = deviceList.selectedDevice, device.isReady {
                        Button("Send files…") {
                            openFilePicker(for: device)
                        }
                        Divider()
                    }

                    Button("Refresh Devices") {
                        Task { await deviceList.refresh() }
                    }

                    Button("Connect Wirelessly…") {
                        showConnectionSheet = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone")
                        Text(deviceList.selectedDevice?.displayName ?? "Devices")
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            TransferToastView()
                .padding()
        }
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
