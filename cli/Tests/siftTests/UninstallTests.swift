import Foundation
import XCTest
@testable import sift

final class UninstallTests: XCTestCase {
    func testOnlyExactBundleIdentifierNamesMatch() {
        let candidates = [
            "/Users/x/Library/Preferences/com.example.app.plist",
            "/Users/x/Library/Caches/com.example.app",
            "/Users/x/Library/Application Support/com.example.app",
            "/Users/x/Library/Caches/com.example.app.helper",
            "/Users/x/Library/Caches/com.example.application",
            "/Users/x/Library/Caches/Com.Example.App",
        ]

        XCTAssertEqual(
            Uninstall.matches(for: "com.example.app", candidates: candidates),
            [
                "/Users/x/Library/Preferences/com.example.app.plist",
                "/Users/x/Library/Caches/com.example.app",
                "/Users/x/Library/Application Support/com.example.app",
                "/Users/x/Library/Caches/Com.Example.App",
            ]
        )
    }

    func testSimilarNamesAreNeverMatched() {
        XCTAssertTrue(Uninstall.matches(for: "com.example.app", candidates: [
            "/Users/x/Library/Caches/com.example.app2",
            "/Users/x/Library/Caches/com.example",
            "/Users/x/Library/Caches/com.other.app",
        ]).isEmpty)
    }

    func testBundleIdentifierIsReadFromInfoPlist() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Example.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try plist(identifier: "com.example.app").write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertEqual(try Uninstall.bundleIdentifier(ofAppAt: app.path), "com.example.app")
    }

    func testMissingOrBlankIdentifierIsRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertThrowsError(try Uninstall.bundleIdentifier(ofAppAt: app.path))

        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try plist(identifier: "   ").write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertThrowsError(try Uninstall.bundleIdentifier(ofAppAt: app.path))
    }

    func testValidateRejectsRelativeAndNonBundlePaths() {
        XCTAssertThrowsError(try Uninstall.parse(["relative/App.app"]).validate())
        XCTAssertThrowsError(try Uninstall.parse(["/tmp/notbundle"]).validate())
    }

    func testScanListsBundleAndLeftoversUnselected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let leftover = directory.appendingPathComponent("com.example.app")
        try Data(repeating: 0x0, count: 128).write(to: leftover)

        let scan = Uninstall.scan(appPath: app.path, bundleID: "com.example.app", leftovers: [leftover.path])
        XCTAssertEqual(scan.groups.count, 2)
        XCTAssertEqual(scan.groups[0].tool, "Application")
        XCTAssertEqual(scan.groups[0].items.map(\.path), [app.path])
        XCTAssertEqual(scan.groups[1].items.map(\.path), [leftover.path])
        XCTAssertTrue(scan.groups.flatMap(\.items).allSatisfy { !$0.selected })
        // Sizes come from the filesystem's allocated size, so only the fact
        // that the leftover was measured matters here.
        XCTAssertGreaterThan(scan.groups[1].items[0].sizeBytes, 0)
    }

    private func plist(identifier: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(identifier)</string>
        </dict></plist>
        """.utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-uninstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
