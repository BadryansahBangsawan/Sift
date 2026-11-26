import XCTest
@testable import Sift

@MainActor
final class AppStateSummaryTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureRoot: URL!
    private var historyStore: CleanupHistoryStore!
    private var savedExclusions: [String]?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedExclusions = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([], forKey: CleanupExclusions.defaultsKey)
        fixtureRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/PureMacTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        historyStore = CleanupHistoryStore(fileURL: fixtureRoot.appendingPathComponent("history.json"))
    }

    override func tearDownWithError() throws {
        if let fixtureRoot { try? fileManager.removeItem(at: fixtureRoot) }
        if let savedExclusions {
            UserDefaults.standard.set(savedExclusions, forKey: CleanupExclusions.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
        }
        try super.tearDownWithError()
    }

    func testBiggestItemsSpansCategoriesAndSkipsTrashAndActionRows() {
        let state = makeState()
        let cache = item("cache", size: 300, category: .userCache)
        let log = item("log", size: 100, category: .systemJunk)
        let derived = item("DerivedData", size: 500, category: .xcodeJunk)
        let prune = CleanableItem(name: "Docker prune", path: "", size: 9_000, category: .dockerCache, isSelected: true, lastModified: nil)
        let trashed = item("trashed", size: 8_000, category: .trash)
        state.categoryResults = [
            .userCache: result(.userCache, [cache]),
            .systemJunk: result(.systemJunk, [log]),
            .xcodeJunk: result(.xcodeJunk, [derived]),
            .dockerCache: result(.dockerCache, [prune]),
            .trash: result(.trash, [trashed]),
        ]

        XCTAssertEqual(state.biggestItems(limit: 2).map(\.name), ["DerivedData", "cache"])
        XCTAssertEqual(state.biggestItems(limit: 10).map(\.name), ["DerivedData", "cache", "log"])
    }

    func testBiggestItemsSkipsOptInItems() {
        let state = makeState()
        let selected = item("cache", size: 300, category: .userCache)
        let optIn = CleanableItem(
            name: "pd-wt",
            path: "/private/tmp/pd-wt",
            size: 52_000_000_000,
            category: .systemJunk,
            isSelected: false,
            lastModified: nil
        )
        state.categoryResults[.systemJunk] = result(.systemJunk, [optIn])
        state.categoryResults[.userCache] = result(.userCache, [selected])

        XCTAssertEqual(state.biggestItems(limit: 3).map(\.name), ["cache"])
    }

    func testBiggestItemsBreaksSizeTiesWithoutLocaleCollation() {
        let state = makeState()
        let lower = item("a", size: 300, category: .userCache)
        let upper = item("B", size: 300, category: .userCache)
        state.categoryResults = [.userCache: result(.userCache, [lower, upper])]

        XCTAssertEqual(
            state.biggestItems(limit: 2).map(\.name),
            ["B", "a"],
            "Equal sizes break by name bytes, not locale collation, so the order is deterministic"
        )
    }

    func testBiggestItemsBreaksEqualNameTiesByPath() {
        let state = makeState()
        let first = CleanableItem(
            name: "same", path: "/private/tmp/a", size: 300, category: .userCache,
            isSelected: true, lastModified: nil
        )
        let second = CleanableItem(
            name: "same", path: "/private/tmp/b", size: 300, category: .userCache,
            isSelected: true, lastModified: nil
        )
        state.categoryResults = [.userCache: result(.userCache, [second, first])]

        XCTAssertEqual(state.biggestItems(limit: 2).map(\.path), ["/private/tmp/a", "/private/tmp/b"])
    }

    func testBiggestItemsHandlesEmptyAndOutOfRangeLimits() {
        let state = makeState()
        XCTAssertTrue(state.biggestItems(limit: 3).isEmpty)

        state.categoryResults = [.userCache: result(.userCache, [item("only", size: 1, category: .userCache)])]
        XCTAssertTrue(state.biggestItems(limit: 0).isEmpty)
        XCTAssertEqual(state.biggestItems(limit: -4).count, 0)
        XCTAssertEqual(state.biggestItems(limit: 50).map(\.name), ["only"])
    }

    func testBiggestItemsOrdersBySizeDescendingAcrossCategories() {
        let state = makeState()
        let small = item("small", size: 10, category: .userCache)
        let large = item("large", size: 1_000, category: .systemJunk)
        let medium = item("medium", size: 100, category: .xcodeJunk)
        state.categoryResults = [
            .userCache: result(.userCache, [small]),
            .systemJunk: result(.systemJunk, [large]),
            .xcodeJunk: result(.xcodeJunk, [medium]),
        ]

        XCTAssertEqual(state.biggestItems(limit: 3).map(\.name), ["large", "medium", "small"])
    }

    func testCategoryGroupsMergeTheirMembers() {
        XCTAssertEqual(CleaningCategory.developerCaches, [.xcodeJunk, .brewCache, .nodeCache, .dockerCache])
        XCTAssertEqual(CleaningCategory.systemJunkGroup, [.systemJunk, .userCache])
        XCTAssertEqual(CleaningCategory.aiToolsGroup, [.aiApps])
    }

    func testCachesChipFollowsTheUserCacheResult() {
        let state = makeState()
        XCTAssertNil(state.cachesSize)
        XCTAssertNil(state.containersSize)
        state.categoryResults[.userCache] = result(.userCache, [item("a", size: 300, category: .userCache), item("b", size: 45, category: .userCache)])
        XCTAssertEqual(state.cachesSize, 345)
    }

    func testThisMonthTotalsComeFromHistory() {
        let now = Date()
        historyStore.record(freedBytes: 1_000, source: .manual, date: now.addingTimeInterval(-70 * 86_400))
        historyStore.record(freedBytes: 20, source: .manual, date: now)
        historyStore.record(freedBytes: 3, source: .scheduled, date: now)
        let state = makeState()

        XCTAssertEqual(state.cleanupsThisMonth.map(\.freedBytes).sorted(), [3, 20])
        XCTAssertEqual(state.freedThisMonth, 23)
    }

    func testCategoryCleanupRecordsItsCategoryAndTitle() async throws {
        let file = fixtureRoot.appendingPathComponent("stale.cache")
        try Data(repeating: 7, count: 4_096).write(to: file)
        let state = makeState()
        let cacheItem = CleanableItem(name: "stale.cache", path: file.path, size: 4_096, category: .userCache, isSelected: true, lastModified: nil)
        state.categoryResults[.userCache] = result(.userCache, [cacheItem])
        state.scanState = .completed

        state.cleanCategory(.userCache)
        for _ in 0..<200 where state.scanState != .cleaned {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(state.scanState, .cleaned)
        let record = try XCTUnwrap(state.cleanupHistory.first)
        XCTAssertEqual(record.category, .userCache)
        XCTAssertEqual(record.title, "User Cache")
        XCTAssertEqual(record.freedBytes, 4_096)
    }

    private func makeState() -> AppState {
        AppState(performStartupTasks: false, historyStore: historyStore)
    }

    private func item(_ name: String, size: Int64, category: CleaningCategory) -> CleanableItem {
        CleanableItem(name: name, path: "/fixtures/\(name)-\(UUID().uuidString)", size: size, category: category, isSelected: true, lastModified: nil)
    }

    private func result(_ category: CleaningCategory, _ items: [CleanableItem]) -> CategoryResult {
        CategoryResult(category: category, items: items, totalSize: items.reduce(0) { $0 + $1.size })
    }
}
