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

    func testSuccessfulRetryDoesNotBringBackTheOldError() async {
        let state = AppState(performStartupTasks: false)
        state.cleanError = "Old failure"
        state.cleanErrorIsFDAFixable = true
        state.presentFullDiskAccessPromptForCleanError()

        await state.retryAfterFullDiskAccess(items: [], context: .cleanup(failedCount: 1))
        state.dismissFullDiskAccessPromptForCleanError()

        XCTAssertNil(state.cleanError)
        XCTAssertFalse(state.cleanErrorIsFDAFixable)
    }

    func testANewerErrorWinsWhenTheSheetCloses() {
        let state = AppState(performStartupTasks: false)
        state.cleanError = "Old failure"
        state.cleanErrorIsFDAFixable = true
        state.presentFullDiskAccessPromptForCleanError()

        state.cleanError = "New failure"
        state.dismissFullDiskAccessPromptForCleanError()

        XCTAssertEqual(state.cleanError, "New failure")
    }

    func testDismissingWithoutAnErrorInventsNothing() {
        let state = AppState(performStartupTasks: false)

        state.presentFullDiskAccessPromptForCleanError()
        state.dismissFullDiskAccessPromptForCleanError()

        XCTAssertNil(state.cleanError)
        XCTAssertFalse(state.cleanErrorIsFDAFixable)
    }

}