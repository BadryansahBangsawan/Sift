import XCTest
@testable import Sift

/// A scanned category keeps its scanned state, even when it ends up empty:
/// otherwise a category the user just emptied falls back to "Cleanup, not
/// scanned yet / Scan this category" and the dashboard row reads "not scanned",
/// which claims the app never looked.
@MainActor
final class CategoryStateAfterCleanTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!

    override func setUpWithError() throws {
        home = fileManager.temporaryDirectory
            .appendingPathComponent("PureMac-CategoryState-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home, fileManager.fileExists(atPath: home.path) {
            try fileManager.removeItem(at: home)
        }
    }

    func testCategoryKeepsItsScannedStateAfterBeingEmptied() async throws {
        let item = try makeCacheItem()
        let state = makeState()
        state.categoryResults[.userCache] = CategoryResult(
            category: .userCache,
            items: [item],
            totalSize: item.size
        )

        state.cleanCategory(.userCache)
        await waitForClean(state)

        let result = try XCTUnwrap(
            state.categoryResults[.userCache],
            "The category was scanned and cleaned: it is not unscanned"
        )
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.totalSize, 0)
    }

    func testScannedEmptyCategorySurvivesACleanOfAnotherCategory() async throws {
        let item = try makeCacheItem()
        let state = makeState()
        state.categoryResults[.userCache] = CategoryResult(
            category: .userCache,
            items: [item],
            totalSize: item.size
        )
        // Installers were scanned and had nothing to offer.
        state.categoryResults[.installers] = CategoryResult(category: .installers, items: [], totalSize: 0)

        state.cleanCategory(.userCache)
        await waitForClean(state)

        XCTAssertNotNil(
            state.categoryResults[.installers],
            "A category scanned with no matches stays scanned after another category is cleaned"
        )
        XCTAssertNotNil(state.categoryResults[.userCache])
    }

    func testTrashKeepsItsScannedStateAfterBeingEmptied() async throws {
        let state = makeState()
        state.categoryResults[.trash] = CategoryResult(
            category: .trash,
            items: [],
            totalSize: 0
        )

        await state.emptyTrash()

        XCTAssertNotNil(
            state.categoryResults[.trash],
            "The Trash page was scanned and emptied; its header must not say 'not scanned yet'"
        )
        XCTAssertEqual(state.categoryResults[.trash]?.items.count, 0)
    }

    // MARK: - Fixtures

    private func makeState() -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false }),
            cleaningEngine: CleaningEngine(homeDirectory: home, isAppRunning: { _ in false }),
            historyStore: CleanupHistoryStore(fileURL: home.appendingPathComponent("history.json")),
            trashEmptier: { nil }
        )
    }

    private func makeCacheItem() throws -> CleanableItem {
        let folder = home.appendingPathComponent("Library/Caches/com.example.app", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8192).write(to: folder.appendingPathComponent("blob.bin"))
        return CleanableItem(
            name: "com.example.app",
            path: folder.path,
            size: 8192,
            category: .userCache,
            isSelected: true,
            lastModified: nil
        )
    }

    private func waitForClean(_ state: AppState, timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !state.scanState.isActive { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Cleanup did not finish")
    }
}
