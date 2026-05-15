import Foundation

struct FileTransferItem: Identifiable {
    let id = UUID()
    let url: URL
    var progress: Double = 0
    var state: TransferState = .pending
    var errorMessage: String?

    enum TransferState {
        case pending, transferring, completed, failed
    }
}

@MainActor
final class FileTransferService: ObservableObject {
    @Published private(set) var transfers: [FileTransferItem] = []
    @Published private(set) var isTransferring = false

    private let adb = AdbService.shared
    private let settings = AppSettings.shared

    func transfer(urls: [URL], to device: AndroidDevice) async {
        guard device.isReady else { return }

        isTransferring = true
        var items = urls.map { FileTransferItem(url: $0) }
        transfers = items

        for index in items.indices {
            items[index].state = .transferring
            transfers = items

            let url = items[index].url
            do {
                try await adb.push(
                    localURL: url,
                    remotePath: settings.transferDestination,
                    serial: device.serial
                ) { [weak self] fraction in
                    Task { @MainActor in
                        guard let self else { return }
                        if index < self.transfers.count {
                            self.transfers[index].progress = fraction
                        }
                    }
                }

                items[index].progress = 1
                items[index].state = .completed
            } catch {
                items[index].state = .failed
                items[index].errorMessage = error.localizedDescription
            }
            transfers = items
        }

        if settings.openDownloadsAfterTransfer, items.contains(where: { $0.state == .completed }) {
            try? await adb.openDownloads(serial: device.serial)
        }

        isTransferring = false
    }

    func clearCompleted() {
        transfers.removeAll { $0.state == .completed }
    }
}
