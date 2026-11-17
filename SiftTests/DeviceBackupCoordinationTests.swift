import XCTest
@testable import Sift

@MainActor
final class DeviceBackupCoordinationTests: XCTestCase {
    func testScheduledScanWaitsUntilBackupRemovalFinishes() {
        let state = AppState(performStartupTasks: false)
        XCTAssertTrue(state.canRunScheduledScan(isAppActive: false))

        state.deviceBackupRemovalInProgress = true
        XCTAssertFalse(state.canRunScheduledScan(isAppActive: false))
        XCTAssertFalse(state.canRunScheduledScan(isAppActive: true))

        state.deviceBackupRemovalInProgress = false
        XCTAssertTrue(state.canRunScheduledScan(isAppActive: false))
    }

    func testBackupRemovalWaitsForActiveScanOrCleanup() {
        let state = AppState(performStartupTasks: false)
        XCTAssertTrue(state.canRemoveDeviceBackups)

        state.scanState = .scanning(progress: 0.5, currentCategory: "Mail Files")
        XCTAssertFalse(state.canRemoveDeviceBackups)
        state.scanState = .cleaning(progress: 0.5)
        XCTAssertFalse(state.canRemoveDeviceBackups)
        state.scanState = .completed
        XCTAssertTrue(state.canRemoveDeviceBackups)
        state.deviceBackupRemovalInProgress = true
        XCTAssertFalse(state.canRemoveDeviceBackups)
    }

    func testManualScansDoNotStartDuringBackupRemoval() {
        let state = AppState(performStartupTasks: false)
        state.deviceBackupRemovalInProgress = true
        state.startSmartScan()
        XCTAssertEqual(state.scanState, .idle)
        state.scanSingleCategory(.userCache)
        XCTAssertEqual(state.scanState, .idle)
    }

    func testManualAndScheduledCleanupWaitForBackupRemoval() {
        let state = AppState(performStartupTasks: false)
        let item = CleanableItem(name: "Fixture", path: "/fixtures/backup", size: 4096,
                                 category: .userCache, isSelected: true, lastModified: nil)
        state.categoryResults[.userCache] = CategoryResult(category: .userCache, items: [item], totalSize: item.size)
        state.scanState = .completed
        state.deviceBackupRemovalInProgress = true

        state.cleanAll()
        XCTAssertEqual(state.scanState, .completed)
        state.cleanAll(scheduled: true)
        XCTAssertEqual(state.scanState, .completed)
        state.cleanCategory(.userCache)
        XCTAssertEqual(state.scanState, .completed)
        XCTAssertEqual(state.categoryResults[.userCache]?.items.map(\.id), [item.id])
    }
}
