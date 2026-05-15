import Foundation

enum BinaryLocatorError: LocalizedError {
    case resourceNotFound(String)
    case notExecutable(String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Bundled binary missing: \(name). Rebuild the app or run scripts/fetch-binaries.sh."
        case .notExecutable(let path):
            return "Binary is not executable: \(path)"
        }
    }
}

struct BinaryLocator {
    static let shared = BinaryLocator()

    private let binariesFolder = "Binaries"

    var adbPath: URL? { try? url(for: "adb") }
    var scrcpyPath: URL? { try? url(for: "scrcpy") }
    var scrcpyServerPath: URL? { try? url(for: "scrcpy-server") }

    var binariesAvailable: Bool {
        guard let adb = try? url(for: "adb").path,
              let scrcpy = try? url(for: "scrcpy").path else { return false }
        return FileManager.default.fileExists(atPath: adb) &&
            FileManager.default.fileExists(atPath: scrcpy)
    }

    func url(for name: String) throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw BinaryLocatorError.resourceNotFound(name)
        }

        let bundled = resourceURL
            .appendingPathComponent(binariesFolder, isDirectory: true)
            .appendingPathComponent(name)

        if FileManager.default.fileExists(atPath: bundled.path) {
            try ensureExecutable(bundled)
            return bundled
        }

        // Development fallback: AndroidMirror/Resources/Binaries next to source
        let devRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/\(binariesFolder)/\(name)")

        if FileManager.default.fileExists(atPath: devRoot.path) {
            try ensureExecutable(devRoot)
            return devRoot
        }

        throw BinaryLocatorError.resourceNotFound(name)
    }

    func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let binDir = (try? url(for: "adb"))?.deletingLastPathComponent().path ?? ""
        if !binDir.isEmpty {
            env["PATH"] = binDir + ":" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            env["ADB"] = (try? url(for: "adb"))?.path
        }
        return env
    }

    private func ensureExecutable(_ url: URL) throws {
        if FileManager.default.isExecutableFile(atPath: url.path) { return }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw BinaryLocatorError.notExecutable(url.path)
        }
    }
}
