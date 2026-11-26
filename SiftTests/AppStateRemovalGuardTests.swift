import XCTest
@testable import Sift

/// Every removal entry point funnels through removeSelectedFiles, so a path
/// that resolves into a high-risk home dotdir must be refused there even when
/// the selection slipped past the scanner-side filters.
@MainActor
final class AppStateRemovalGuardTests: XCTestCase {
    func testRemovalRefusesAHighRiskHomeDotPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // ~/.pypirc is in highRiskHomeDotPaths. The guard runs before any
        // filesystem change, so this test only uses the path's resolved name
        // and never creates, trashes or deletes it.
        let guarded = (home as NSString).appendingPathComponent(".pypirc")
        let state = AppState(performStartupTasks: false)

        state.removeSelectedFiles(confirmedURLs: [URL(fileURLWithPath: guarded)])

        XCTAssertFalse(state.isRemovingAppFiles, "the refused batch never starts a removal")
        XCTAssertEqual(
            state.removalError?.contains("protected item"),
            true,
            "expected the protected-item refusal, got \(state.removalError ?? "nil")"
        )
        XCTAssertTrue(state.selectedFiles.isEmpty)
    }
}