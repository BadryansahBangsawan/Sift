import XCTest
@testable import PureMac

@MainActor
final class AppStateTrashTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureHome: URL!
    private var trash: URL!
    private var historyStore: CleanupHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureHome = fileManager.temporaryDirectory
            .appendingPathComponent("AppStateTrashTests-\(UUID().uuidString)", isDirectory: true)
        trash = fixtureHome.appendingPathComponent(".Trash", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        historyStore = CleanupHistoryStore(fileURL: fixtureHome.appendingPathComponent("history.json"))
    }

    override func tearDownWithError() throws {
        if let fixtureHome { try? fileManager.removeItem(at: fixtureHome) }
        try super.tearDownWithError()
    }

    func testEmptyTrashAsksFinderAndRecordsWhatWasFreed() async throws {
        try Data(repeating: 1, count: 8_192).write(to: trash.appendingPathComponent("old.bin"))
        var finderCalls = 0
        let state = makeState { [trash, fileManager] in
            finderCalls += 1
            // Stand-in for Finder emptying the Trash.
            for entry in try! fileManager.contentsOfDirectory(at: trash!, includingPropertiesForKeys: nil) {
                try? fileManager.removeItem(at: entry)
            }
            return nil
        }

        await state.emptyTrash()

        XCTAssertEqual(finderCalls, 1)
        XCTAssertNil(state.cleanError)
        XCTAssertNil(state.categoryResults[.trash])
        XCTAssertFalse(state.isEmptyingTrash)
        let record = try XCTUnwrap(state.cleanupHistory.first)
        XCTAssertEqual(record.category, .trash)
        XCTAssertEqual(record.title, "Emptied Trash")
        XCTAssertGreaterThanOrEqual(record.freedBytes, 8_192)
        XCTAssertEqual(historyStore.load().count, 1)
    }

    func testFinderFailureKeepsTrashAndReportsTheError() async throws {
        try Data(repeating: 1, count: 8_192).write(to: trash.appendingPathComponent("old.bin"))
        let state = makeState { "Finder refused" }

        await state.emptyTrash()

        XCTAssertEqual(state.cleanError, "Finder refused")
        XCTAssertEqual(state.categoryResults[.trash]?.itemCount, 1)
        XCTAssertTrue(state.cleanupHistory.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: trash.appendingPathComponent("old.bin").path))
    }

    func testBulkCleanIgnoresTrashItemsEvenWhenSelected() throws {
        let file = trash.appendingPathComponent("kept.bin")
        try Data(repeating: 1, count: 4_096).write(to: file)
        let state = makeState { XCTFail("Finder must not be asked"); return nil }
        let item = CleanableItem(name: "kept.bin", path: file.path, size: 4_096, category: .trash, isSelected: false, lastModified: nil)
        state.categoryResults[.trash] = CategoryResult(category: .trash, items: [item], totalSize: item.size)
        state.scanState = .completed
        state.toggleItem(item)
        XCTAssertTrue(state.isItemSelected(item))

        XCTAssertEqual(state.totalSelectedSize, 0)
        state.cleanAll()
        XCTAssertEqual(state.scanState, .completed)
        state.cleanAll(scheduled: true)
        XCTAssertEqual(state.scanState, .completed)
        state.cleanCategory(.trash)
        XCTAssertEqual(state.scanState, .completed)
        XCTAssertTrue(fileManager.fileExists(atPath: file.path))
    }

    private func makeState(trashEmptier: @escaping AppState.TrashEmptier) -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: fixtureHome),
            historyStore: historyStore,
            trashEmptier: trashEmptier
        )
    }
}
