import XCTest
@testable import Sift

/// Views and tests talk to `AppUpdateController`; Sparkle only appears behind
/// `UpdaterBridge`, so these tests use a fake and never start the real updater.
@MainActor
final class AppUpdateControllerTests: XCTestCase {
    func testCheckForUpdatesAsksTheUpdater() {
        let bridge = FakeUpdaterBridge()
        let controller = AppUpdateController(bridge: bridge)

        controller.checkForUpdates()

        XCTAssertEqual(bridge.checkCount, 1)
    }

    func testAutomaticCheckToggleReadsAndWritesThrough() {
        let bridge = FakeUpdaterBridge()
        let controller = AppUpdateController(bridge: bridge)

        controller.automaticallyChecksForUpdates = true
        XCTAssertTrue(bridge.automaticallyChecksForUpdates)

        controller.automaticallyChecksForUpdates = false
        XCTAssertFalse(bridge.automaticallyChecksForUpdates)
    }

    func testAutomaticDownloadToggleReadsAndWritesThrough() {
        let bridge = FakeUpdaterBridge()
        bridge.automaticallyChecksForUpdates = true
        let controller = AppUpdateController(bridge: bridge)

        XCTAssertTrue(controller.canAutomaticallyDownloadUpdates)
        controller.automaticallyDownloadsUpdates = true
        XCTAssertTrue(bridge.automaticallyDownloadsUpdates)
    }

    func testDownloadToggleIsOffWhileAutomaticChecksAreOff() {
        let bridge = FakeUpdaterBridge()
        bridge.automaticallyChecksForUpdates = false
        let controller = AppUpdateController(bridge: bridge)

        XCTAssertFalse(controller.canAutomaticallyDownloadUpdates)

        controller.automaticallyChecksForUpdates = true
        XCTAssertTrue(controller.canAutomaticallyDownloadUpdates)
    }

    func testMenuCommandEnabledStateFollowsTheUpdater() {
        let bridge = FakeUpdaterBridge()
        let controller = AppUpdateController(bridge: bridge)

        bridge.canCheckForUpdates = false
        XCTAssertFalse(controller.canCheckForUpdates)

        bridge.canCheckForUpdates = true
        XCTAssertTrue(controller.canCheckForUpdates)
    }
}

@MainActor
private final class FakeUpdaterBridge: UpdaterBridge {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = false
    var automaticallyDownloadsUpdates = false
    var onChange: (() -> Void)?
    private(set) var checkCount = 0

    func checkForUpdates() {
        checkCount += 1
    }
}
