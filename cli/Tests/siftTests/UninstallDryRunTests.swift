import Darwin
import Foundation
import XCTest
@testable import sift

/// `uninstall --dry-run` lists the matched set but its summary must count what
/// a real uninstall would remove, not the unselected review state.
final class UninstallDryRunTests: XCTestCase {
    private var fixture: URL!
    private var savedHome: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-dryrun-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        savedHome = ProcessInfo.processInfo.environment["HOME"]
        setenv("HOME", fixture.path, 1)
    }

    override func tearDownWithError() throws {
        if let savedHome {
            setenv("HOME", savedHome, 1)
        } else {
            unsetenv("HOME")
        }
        if let fixture { try? FileManager.default.removeItem(at: fixture) }
        try super.tearDownWithError()
    }

    func testDryRunSummaryCountsTheMatchedSet() throws {
        let app = try makeApp(name: "Example.app", bundleID: "com.example.dryrun")

        let output = try captureStandardOutput {
            try Uninstall.parse([app.path, "--dry-run"]).run()
        }

        XCTAssertTrue(
            output.contains("reclaimable across 1 item"),
            "the dry run must count the app it would remove, got:\n\(output)"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path), "a dry run never deletes")
    }

    // MARK: - Fixtures

    private func makeApp(name: String, bundleID: String) throws -> URL {
        let app = fixture.appendingPathComponent(name, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        </dict></plist>
        """.utf8)
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    private func captureStandardOutput(_ body: () throws -> Void) rethrows -> String {
        let pipe = Pipe()
        fflush(stdout)
        let saved = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        try body()
        fflush(stdout)
        // Restore fd 1 before reading: the duplicated write end would keep the
        // pipe open and readDataToEndOfFile would wait forever.
        dup2(saved, STDOUT_FILENO)
        close(saved)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}