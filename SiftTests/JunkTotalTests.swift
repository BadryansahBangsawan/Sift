import XCTest
@testable import Sift

/// The Overview headline and disk meter call the total "junk", but Large &
/// old files and the Trash are the user's own files: they show their own sizes
/// and stay out of that total.
@MainActor
final class JunkTotalTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureHome: URL!
    private var historyStore: CleanupHistoryStore!
    private var savedExclusions: [String]?

    private let mb: Int64 = 1024 * 1024

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedExclusions = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([], forKey: CleanupExclusions.defaultsKey)
        fixtureHome = fileManager.temporaryDirectory
            .appendingPathComponent("JunkTotalTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
        historyStore = CleanupHistoryStore(fileURL: fixtureHome.appendingPathComponent("history.json"))
    }

    override func tearDownWithError() throws {
        if let fixtureHome { try? fileManager.removeItem(at: fixtureHome) }
        if let savedExclusions {
            UserDefaults.standard.set(savedExclusions, forKey: CleanupExclusions.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
        }
        try super.tearDownWithError()
    }

    func testTheJunkTotalCountsOnlyJunkCategories() {
        let state = makeState()
        state.categoryResults = [
            .systemJunk: result(.systemJunk, 10 * mb),
            .largeFiles: result(.largeFiles, 200 * mb),
            .trash: result(.trash, 50 * mb),
        ]

        // Any recompute path: excluding a row goes through the same total.
        state.excludeFromCleanup(item("dummy", category: .systemJunk, size: 0))

        XCTAssertEqual(state.totalJunkSize, 10 * mb)
    }

    // MARK: - Fixtures

    private func makeState() -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: fixtureHome),
            historyStore: historyStore
        )
    }

    private func item(_ name: String, category: CleaningCategory, size: Int64) -> CleanableItem {
        CleanableItem(
            name: name,
            path: "/fixtures/\(name)-\(UUID().uuidString)",
            size: size,
            category: category,
            isSelected: true,
            lastModified: nil
        )
    }

    private func result(_ category: CleaningCategory, _ size: Int64) -> CategoryResult {
        CategoryResult(category: category, items: [item("row", category: category, size: size)], totalSize: size)
    }
}
