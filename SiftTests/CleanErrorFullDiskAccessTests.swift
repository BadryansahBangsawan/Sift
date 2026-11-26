import XCTest
@testable import Sift

/// A clean that needs Full Disk Access shows the permission sheet, but
/// dismissing it must not erase the reason the clean failed.
@MainActor
final class CleanErrorFullDiskAccessTests: XCTestCase {
    func testDismissingTheFullDiskAccessSheetKeepsTheCleanError() {
        let state = AppState(performStartupTasks: false)
        state.cleanError = "Couldn't remove 2 files."
        state.cleanErrorIsFDAFixable = true

        state.presentFullDiskAccessPromptForCleanError()
        state.dismissFullDiskAccessPromptForCleanError()

        XCTAssertEqual(state.cleanError, "Couldn't remove 2 files.")
        XCTAssertFalse(state.cleanErrorIsFDAFixable)
    }
}