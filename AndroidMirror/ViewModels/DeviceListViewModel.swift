import Foundation

@MainActor
final class DeviceListViewModel: ObservableObject {
    @Published var devices: [AndroidDevice] = []
    @Published var selectedDevice: AndroidDevice?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pairHost = ""
    @Published var pairPort = "5555"
    @Published var pairCode = ""
    @Published var connectPort = "5555"
    @Published var isPairing = false

    private let adb = AdbService.shared
    private var pollTask: Task<Void, Never>?

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        isLoading = devices.isEmpty
        defer { isLoading = false }

        do {
            let list = try await adb.listDevices()
            devices = list

            if let selected = selectedDevice,
               let updated = list.first(where: { $0.id == selected.id }) {
                selectedDevice = updated
            } else if selectedDevice == nil {
                selectedDevice = list.first(where: \.isReady)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ device: AndroidDevice?) {
        selectedDevice = device
    }

    func pairWireless() async {
        guard let port = Int(pairPort) else {
            errorMessage = "Invalid pair port."
            return
        }
        isPairing = true
        defer { isPairing = false }

        do {
            try await adb.pair(host: pairHost, port: port, code: pairCode)
            if let connectPort = Int(connectPort) {
                try await adb.connect(host: pairHost, port: connectPort)
            }
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connectWireless() async {
        guard let port = Int(connectPort) else {
            errorMessage = "Invalid connect port."
            return
        }
        isPairing = true
        defer { isPairing = false }

        do {
            try await adb.connect(host: pairHost, port: port)
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
