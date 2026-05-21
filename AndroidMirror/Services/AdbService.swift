import Foundation

enum AdbServiceError: LocalizedError {
    case commandFailed(String)
    case binariesMissing

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        case .binariesMissing: return BinaryLocatorError.resourceNotFound("adb").errorDescription
        }
    }
}

actor AdbService {
    static let shared = AdbService()

    private let locator = BinaryLocator.shared

    func listDevices() async throws -> [AndroidDevice] {
        let lines = try await adb(["devices", "-l"])
        return parseDevices(lines: lines)
    }

    func pair(host: String, port: Int, code: String) async throws {
        let result = try await runAdb(["pair", "\(host):\(port)", code])
        guard result.succeeded else {
            throw AdbServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    func connect(host: String, port: Int) async throws {
        let result = try await runAdb(["connect", "\(host):\(port)"])
        guard result.succeeded || result.stdout.contains("connected") else {
            throw AdbServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
    }

    func disconnect(serial: String? = nil) async throws {
        if let serial {
            _ = try await runAdb(["disconnect", serial])
        } else {
            _ = try await runAdb(["disconnect"])
        }
    }

    func push(
        localURL: URL,
        remotePath: String,
        serial: String,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let remote = remotePath.hasSuffix("/")
            ? remotePath + localURL.lastPathComponent
            : remotePath

        if let progress {
            try await pushWithProgress(localURL: localURL, remote: remote, serial: serial, progress: progress)
        } else {
            let result = try await runAdb(["-s", serial, "push", localURL.path, remote])
            guard result.succeeded else {
                throw AdbServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
            }
        }
    }

    func shell(_ command: String, serial: String) async throws -> String {
        let result = try await runAdb(["-s", serial, "shell", command])
        guard result.succeeded else {
            throw AdbServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
    }

    func openDownloads(serial: String) async throws {
        _ = try await shell(
            "am start -a android.intent.action.VIEW -d content://com.android.externalstorage.documents/document/primary:Download",
            serial: serial
        )
    }

    // MARK: - Private

    private func adb(_ args: [String]) async throws -> [String] {
        try await ProcessRunner.runLines(
            executable: try locator.url(for: "adb"),
            arguments: args,
            environment: locator.environment()
        )
    }

    private func runAdb(_ args: [String]) async throws -> ProcessResult {
        try await ProcessRunner.run(
            executable: try locator.url(for: "adb"),
            arguments: args,
            environment: locator.environment()
        )
    }

    private func pushWithProgress(
        localURL: URL,
        remote: String,
        serial: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            do {
                process.executableURL = try locator.url(for: "adb")
            } catch {
                continuation.resume(throwing: error)
                return
            }

            process.arguments = ["-s", serial, "push", localURL.path, remote]
            process.environment = locator.environment()

            let errPipe = Pipe()
            process.standardOutput = Pipe()
            process.standardError = errPipe

            let bufferLock = NSLock()
            var buffer = Data()

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                bufferLock.lock()
                buffer.append(chunk)
                let text = String(data: buffer, encoding: .utf8)
                bufferLock.unlock()
                if let text, let fraction = AdbService.parsePushProgress(text, fileSize: fileSize) {
                    progress(fraction)
                }
            }

            process.terminationHandler = { proc in
                errPipe.fileHandleForReading.readabilityHandler = nil
                bufferLock.lock()
                let errText = String(data: buffer, encoding: .utf8) ?? "adb push failed"
                bufferLock.unlock()
                if proc.terminationStatus == 0 {
                    progress(1.0)
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AdbServiceError.commandFailed(errText))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func parsePushProgress(_ text: String, fileSize: Int64) -> Double? {
        // adb push reports: [ 45%] /path/to/file
        guard let range = text.range(of: #"\[\s*(\d+)%\]"#, options: .regularExpression) else { return nil }
        let match = String(text[range])
        let digits = match.filter(\.isNumber)
        guard let percent = Int(digits) else { return nil }
        if fileSize > 0 {
            return min(1.0, Double(percent) / 100.0)
        }
        return Double(percent) / 100.0
    }

    func parseDevices(lines: [String]) -> [AndroidDevice] {
        lines
            .dropFirst()
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> AndroidDevice? in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 2 else { return nil }

                let serial = parts[0]
                let state = DeviceState(rawValue: parts[1]) ?? .unknown

                var model = ""
                var product = ""
                for part in parts.dropFirst(2) {
                    if part.hasPrefix("model:") { model = String(part.dropFirst(6)) }
                    if part.hasPrefix("product:") { product = String(part.dropFirst(8)) }
                }

                let transport: DeviceTransport = serial.contains(":") ? .wifi : .usb

                return AndroidDevice(
                    id: serial,
                    model: model,
                    product: product,
                    transport: transport,
                    state: state
                )
            }
    }
}
