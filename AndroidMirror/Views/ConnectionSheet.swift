import SwiftUI

struct ConnectionSheet: View {
    @EnvironmentObject private var deviceList: DeviceListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("On your phone: Settings → Developer options → Wireless debugging → Pair device with pairing code.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Wireless pairing (Android 11+)") {
                    TextField("Host (IP address)", text: $deviceList.pairHost)
                    TextField("Pairing port", text: $deviceList.pairPort)
                    TextField("Pairing code", text: $deviceList.pairCode)
                    Button("Pair") {
                        Task { await deviceList.pairWireless() }
                    }
                    .disabled(deviceList.pairHost.isEmpty || deviceList.pairCode.isEmpty || deviceList.isPairing)
                }

                Section("Connect") {
                    TextField("Connect port", text: $deviceList.connectPort)
                    Button("Connect") {
                        Task { await deviceList.connectWireless() }
                    }
                    .disabled(deviceList.pairHost.isEmpty || deviceList.isPairing)
                }

                Section("USB") {
                    Label("Enable USB debugging on your device", systemImage: "1.circle")
                    Label("Tap “Allow” when prompted to trust this Mac", systemImage: "2.circle")
                    Label("On Xiaomi/Redmi: also enable USB debugging (Security Settings)", systemImage: "exclamationmark.triangle")
                }

                if let error = deviceList.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        Task { await deviceList.refresh() }
                    }
                }
            }
        }
        .frame(width: 440, height: 520)
    }
}
