import XCTest
@testable import Sift

/// Locks down the exact AppleScript Sift runs when the user approves removing
/// orphaned files as an administrator. The tests swap `/bin/rm -rf --` for a
/// harmless command that echoes its arguments, so they never delete anything
/// and never ask for administrator privileges.
final class ShellQuotingTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellQuotingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture { try? FileManager.default.removeItem(at: fixture) }
    }

    func testRemovalScriptPassesPathsVerbatimAndRunsNoPayload() throws {
        let marker = fixture.appendingPathComponent("INJECTED")
        let captured = fixture.appendingPathComponent("arguments.bin")
        let paths = [
            "\(fixture.path)/a'; /usr/bin/touch \(marker.path) #",
            "\(fixture.path)/it's",
        ]

        let result = try runRemovalScript(paths: paths, capturingArgumentsTo: captured)

        XCTAssertEqual(result.status, 0, "osascript failed: \(result.stderr)")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: marker.path),
            "a crafted folder name ran a command"
        )
        XCTAssertEqual(try Data(contentsOf: captured), nulSeparated(paths))
    }

    // MARK: - Helpers

    /// Builds the production AppleScript shape with `sh` in place of `rm`: the
    /// script writes its NUL-separated arguments to `captured`, so the bytes
    /// prove exactly which words the shell received.
    private func runRemovalScript(
        paths: [String],
        capturingArgumentsTo captured: URL
    ) throws -> (status: Int32, stderr: String) {
        let script = ShellQuoting.removalAppleScript(
            paths: paths,
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s\\0' \"$@\" > \"$0\"", captured.path]
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: errorData, as: UTF8.self))
    }

    private func nulSeparated(_ paths: [String]) -> Data {
        var data = Data()
        for path in paths {
            data.append(Data(path.utf8))
            data.append(0)
        }
        return data
    }
}