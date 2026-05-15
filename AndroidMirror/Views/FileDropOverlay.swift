import SwiftUI
import UniformTypeIdentifiers

struct FileDropOverlay: ViewModifier {
    let device: AndroidDevice?
    @EnvironmentObject private var fileTransfer: FileTransferService
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .background(Color.accentColor.opacity(0.12))
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.largeTitle)
                                Text("Drop to send to device")
                                    .font(.headline)
                            }
                        }
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                guard let device, device.isReady else { return false }
                loadFiles(from: providers, device: device)
                return true
            }
    }

    private func loadFiles(from providers: [NSItemProvider], device: AndroidDevice) {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            await fileTransfer.transfer(urls: urls, to: device)
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let path = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: URL(string: path))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension View {
    func fileDropOverlay(device: AndroidDevice?) -> some View {
        modifier(FileDropOverlay(device: device))
    }
}

struct TransferToastView: View {
    @EnvironmentObject private var fileTransfer: FileTransferService

    var body: some View {
        if fileTransfer.isTransferring || fileTransfer.transfers.contains(where: { $0.state == .failed || $0.state == .completed }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("File transfer")
                        .font(.headline)
                    Spacer()
                    if !fileTransfer.isTransferring {
                        Button("Dismiss") {
                            fileTransfer.clearCompleted()
                        }
                    }
                }

                ForEach(fileTransfer.transfers.prefix(3)) { item in
                    HStack {
                        Image(systemName: icon(for: item.state))
                            .foregroundStyle(color(for: item.state))
                        Text(item.url.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        if item.state == .transferring {
                            ProgressView(value: item.progress)
                                .frame(width: 80)
                        }
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8)
        }
    }

    private func icon(for state: FileTransferItem.TransferState) -> String {
        switch state {
        case .pending: return "clock"
        case .transferring: return "arrow.up.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func color(for state: FileTransferItem.TransferState) -> Color {
        switch state {
        case .completed: return .green
        case .failed: return .red
        default: return .accentColor
        }
    }
}
