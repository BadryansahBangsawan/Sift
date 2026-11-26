import XCTest
@testable import Sift

/// The Trash is read-only in Sift: the page lists what is in `~/.Trash`, and
/// the user empties it in Finder. No AppState entry point removes those rows.
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

    func testScanningTheTrashListsReadOnlyRows() async throws {
        try Data(repeating: 1, count: 8_192).write(to: trash.appendingPathComponent("old.bin"))
        try Data(repeating: 2, count: 4_096).write(to: trash.appendingPathComponent("older.bin"))

        let scanned = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.trash)

        XCTAssertEqual(Set(scanned.items.map(\.name)), ["old.bin", "older.bin"])
        XCTAssertTrue(scanned.items.allSatisfy { $0.category == .trash })
        XCTAssertTrue(scanned.items.allSatisfy { !$0.isSelected }, "Nothing in the Trash is preselected")
    }

    func testBulkCleanIgnoresTrashItemsEvenWhenSelected() throws {
        let file = trash.appendingPathComponent("kept.bin")
        try Data(repeating: 1, count: 4_096).write(to: file)
        let state = makeState()
        let item = CleanableItem(
            name: "kept.bin",
            path: file.path,
            size: 4_096,
            category: .trash,
            isSelected: false,
            lastModified: nil
        )
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

    func testRetryingATrashRowLeavesItAndWritesNoHistory() async throws {
        let file = trash.appendingPathComponent("kept.bin")
        try Data(repeating: 3, count: 4_096).write(to: file)
        let scanned = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.trash)
        let item = try XCTUnwrap(scanned.items.first { $0.name == "kept.bin" })
        let state = makeState()
        state.categoryResults[.trash] = scanned

        await state.retryAfterFullDiskAccess(items: [item], context: .cleanup(failedCount: 1))

        XCTAssertTrue(fileManager.fileExists(atPath: file.path), "A retry never empties the Trash")
        XCTAssertTrue(state.cleanupHistory.isEmpty)
    }

    private func makeState() -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: fixtureHome),
            historyStore: historyStore
        )
    }
}