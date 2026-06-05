import XCTest
@testable import Android_Mirror

/// Tests for BinaryLocator.
/// Covers test plan items: 1.3, 1.5
final class BinaryLocatorTests: XCTestCase {

    /// 1.3: Missing binary throws resourceNotFound
    func testMissingBinaryThrows() {
        let locator = BinaryLocator.shared
        XCTAssertThrowsError(try locator.url(for: "nonexistent_binary_xyz")) { error in
            guard let locatorError = error as? BinaryLocatorError else {
                XCTFail("Expected BinaryLocatorError, got \(error)")
                return
            }
            if case .resourceNotFound(let name) = locatorError {
                XCTAssertEqual(name, "nonexistent_binary_xyz")
            } else {
                XCTFail("Expected resourceNotFound, got \(locatorError)")
            }
        }
    }

    /// 1.5: Environment PATH contains Binaries directory
    func testEnvironmentPath() {
        let locator = BinaryLocator.shared
        let env = locator.environment()

        // PATH should exist
        XCTAssertNotNil(env["PATH"])

        // If adb exists, Binaries dir should be in PATH
        if let adbURL = try? locator.url(for: "adb") {
            let binDir = adbURL.deletingLastPathComponent().path
            XCTAssertTrue(env["PATH"]!.contains(binDir),
                          "PATH should contain the Binaries directory: \(binDir)")
        }
    }

    func testRunLinesThrowsOnNonZeroExit() async {
        let executable = URL(fileURLWithPath: "/bin/sh")

        do {
            _ = try await ProcessRunner.runLines(
                executable: executable,
                arguments: ["-c", "echo failure >&2; exit 2"]
            )
            XCTFail("Expected runLines to throw for a non-zero exit code")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("failure"))
        }
    }
}
