import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

enum ProcessRunnerError: LocalizedError {
    case commandFailed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let exitCode, let output):
            if output.isEmpty {
                return "Process failed with exit code \(exitCode)."
            }
            return output
        }
    }
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = environment ?? ProcessInfo.processInfo.environment

            if let currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: ProcessResult(
                    exitCode: proc.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func runLines(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) async throws -> [String] {
        let result = try await run(executable: executable, arguments: arguments, environment: environment)
        guard result.succeeded else {
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ProcessRunnerError.commandFailed(exitCode: result.exitCode, output: message)
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }
}
