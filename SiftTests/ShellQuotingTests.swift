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
        try assertRoundTrip(
            [
                "\(fixture.path)/a'; /usr/bin/touch \(marker.path) #",
                "\(fixture.path)/it's",
            ],
            markers: [marker]
        )
    }

    /// Everything a shell treats specially, in one name: an injection attempt,
    /// command substitution, backticks, both quote characters, a backslash,
    /// spaces and non-ASCII text.
    func testShellMetacharactersInOnePathSurvive() throws {
        let marker = fixture.appendingPathComponent("METACHARS")
        let path = "\(fixture.path)/it's $(/usr/bin/touch \(marker.path)) `echo nope` \"quote\" back\\slash; # hash 漢字 cafe\u{0301}"
        try assertRoundTrip([path], markers: [marker])
    }

    func testSeveralAwkwardPathsAtOnce() throws {
        let firstMarker = fixture.appendingPathComponent("MULTI-1")
        let secondMarker = fixture.appendingPathComponent("MULTI-2")
        let paths = [
            "\(fixture.path)/one; /usr/bin/touch \(firstMarker.path)",
            "\(fixture.path)/two's",
            "\(fixture.path)/three $(/usr/bin/touch \(secondMarker.path))",
            "\(fixture.path)/four\\backslash",
            "\(fixture.path)/five with spaces",
            "\(fixture.path)/six 漢字 cafe\u{0301}",
        ]
        try assertRoundTrip(paths, markers: [firstMarker, secondMarker])
    }

    func testPathMadeOnlyOfQuotesSurvives() throws {
        let paths = [
            "\(fixture.path)/'",
            "\(fixture.path)/'''",
            "\(fixture.path)/'\"'",
        ]
        try assertRoundTrip(paths, markers: [])
    }

    func testPathWithNewlineAndTabSurvives() throws {
        let marker = fixture.appendingPathComponent("NEWLINE")
        let paths = [
            "\(fixture.path)/line\nbreak'; /usr/bin/touch \(marker.path) #",
            "\(fixture.path)/tab\tseparated",
        ]
        try assertRoundTrip(paths, markers: [marker])
    }

    // MARK: - Helpers

    private func assertRoundTrip(
        _ paths: [String],
        markers: [URL],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let captured = fixture.appendingPathComponent("arguments-\(UUID().uuidString).bin")
        let result = try runRemovalScript(paths: paths, capturingArgumentsTo: captured)

        XCTAssertEqual(result.status, 0, "osascript failed: \(result.stderr)", file: file, line: line)
        for marker in markers {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: marker.path),
                "a crafted folder name ran a command",
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: captured),
            nulSeparated(paths),
            file: file,
            line: line
        )
    }

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