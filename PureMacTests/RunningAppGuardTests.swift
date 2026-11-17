import AppKit
import XCTest
@testable import PureMac

final class RunningAppGuardTests: XCTestCase {
    func testRemovalIsBlockedWhileTheAppIsRunning() {
        let guardian = RunningAppGuard(bundleIdentifier: "com.example.editor") { _, _ in true }

        XCTAssertTrue(guardian.isRunning)
        XCTAssertFalse(guardian.canRemove)
    }

    func testRemovalIsAllowedWhenTheAppIsNotRunning() {
        let guardian = RunningAppGuard(bundleIdentifier: "com.example.editor") { _, _ in false }

        XCTAssertFalse(guardian.isRunning)
        XCTAssertTrue(guardian.canRemove)
    }

    func testCheckReceivesTheAppsBundleIdentifierAndURL() {
        let app = InstalledApp(
            id: UUID(),
            appName: "Editor",
            bundleIdentifier: "com.example.editor",
            path: URL(fileURLWithPath: "/Applications/Editor.app"),
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            size: 1
        )
        var seen: (String, URL?)?
        let guardian = RunningAppGuard(app: app) { id, url in
            seen = (id, url)
            return false
        }

        _ = guardian.isRunning

        XCTAssertEqual(seen?.0, "com.example.editor")
        XCTAssertEqual(seen?.1, URL(fileURLWithPath: "/Applications/Editor.app"))
    }

    func testSystemCheckReportsAnUnknownAppAsNotRunning() {
        let guardian = RunningAppGuard(
            bundleIdentifier: "test.puremac.not-running.\(UUID().uuidString)",
            appURL: URL(fileURLWithPath: "/nonexistent/NotRunning.app")
        )

        XCTAssertFalse(guardian.isRunning)
        XCTAssertTrue(guardian.canRemove)
        XCTAssertFalse(guardian.requestQuit())
    }
}
