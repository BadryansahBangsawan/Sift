import XCTest
@testable import Sift

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

    func testSurvivingExcludedTrashItemIsNotCountedAsFreed() async throws {
        let gone = trash.appendingPathComponent("gone.bin")
        let kept = trash.appendingPathComponent("keep.bin")
        try Data(repeating: 1, count: 8_192).write(to: gone)
        try Data(repeating: 2, count: 12_288).write(to: kept)

        let scanned = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.trash)
        let goneSize = try XCTUnwrap(scanned.items.first { $0.name == "gone.bin" }?.size)

        let saved = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([kept.path], forKey: CleanupExclusions.defaultsKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: CleanupExclusions.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
            }
        }

        let state = makeState { [trash, fileManager] in
            // Finder empties what it can; the excluded, in-use file survives.
            for entry in try! fileManager.contentsOfDirectory(at: trash!, includingPropertiesForKeys: nil)
            where entry.lastPathComponent != "keep.bin" {
                try? fileManager.removeItem(at: entry)
            }
            return nil
        }

        await state.emptyTrash()

        XCTAssertTrue(fileManager.fileExists(atPath: kept.path))
        let record = try XCTUnwrap(state.cleanupHistory.first)
        XCTAssertEqual(
            record.freedBytes,
            goneSize,
            "Only the row the user saw removed was freed; the excluded survivor is still on disk"
        )
    }

    func testFullyExcludedTrashRecordsNoFreedSpace() async throws {
        let kept = trash.appendingPathComponent("keep.bin")
        try Data(repeating: 3, count: 8_192).write(to: kept)

        let saved = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([kept.path], forKey: CleanupExclusions.defaultsKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: CleanupExclusions.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
            }
        }

        let state = makeState { [trash, fileManager] in
            for entry in try! fileManager.contentsOfDirectory(at: trash!, includingPropertiesForKeys: nil) {
                try? fileManager.removeItem(at: entry)
            }
            return nil
        }

        await state.emptyTrash()

        XCTAssertFalse(fileManager.fileExists(atPath: kept.path))
        XCTAssertTrue(
            state.cleanupHistory.isEmpty,
            "Nothing the user could see was removed, so nothing may be recorded as freed"
        )
    }

    func testVisibleTrashRowsStillRecordTheirFullSize() async throws {
        try Data(repeating: 4, count: 8_192).write(to: trash.appendingPathComponent("a.bin"))
        try Data(repeating: 5, count: 8_192).write(to: trash.appendingPathComponent("b.bin"))
        let scanned = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.trash)
        let expected = scanned.totalSize

        let saved = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([], forKey: CleanupExclusions.defaultsKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: CleanupExclusions.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
            }
        }

        let state = makeState { [trash, fileManager] in
            for entry in try! fileManager.contentsOfDirectory(at: trash!, includingPropertiesForKeys: nil) {
                try? fileManager.removeItem(at: entry)
            }
            return nil
        }

        await state.emptyTrash()

        XCTAssertEqual(state.cleanupHistory.first?.freedBytes, expected)
    }

    func testTrashCategoryKeepsOnlyTheRowsTheUserCanSee() async throws {
        let kept = trash.appendingPathComponent("keep.bin")
        try Data(repeating: 6, count: 8_192).write(to: kept)

        let saved = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([kept.path], forKey: CleanupExclusions.defaultsKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: CleanupExclusions.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
            }
        }

        let state = makeState { nil }

        await state.emptyTrash()

        XCTAssertTrue(fileManager.fileExists(atPath: kept.path))
        XCTAssertNil(state.categoryResults[.trash])
        XCTAssertEqual(state.totalJunkSize, 0)
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
