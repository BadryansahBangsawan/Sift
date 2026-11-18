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

    func testCategoryGroupsMergeTheirMembers() {
        XCTAssertEqual(CleaningCategory.developerCaches, [.xcodeJunk, .brewCache, .nodeCache, .dockerCache])
        XCTAssertEqual(CleaningCategory.systemJunkGroup, [.systemJunk, .userCache, .aiApps])

        let state = makeState()
        let derived = item("DerivedData", size: 500, category: .xcodeJunk)
        let brew = item("Homebrew", size: 200, category: .brewCache)
        let npm = item("npm", size: 50, category: .nodeCache)
        let cache = item("cache", size: 300, category: .userCache)
        state.categoryResults = [
            .xcodeJunk: result(.xcodeJunk, [derived]),
            .brewCache: result(.brewCache, [brew, npm].filter { $0.category == .brewCache }),
            .nodeCache: result(.nodeCache, [npm]),
            .userCache: result(.userCache, [cache]),
        ]

        let developer = state.groupResult(for: CleaningCategory.developerCaches)
        XCTAssertEqual(developer.categories, CleaningCategory.developerCaches)
        XCTAssertEqual(developer.totalSize, 750)
        XCTAssertEqual(developer.itemCount, 3)
        XCTAssertEqual(Set(developer.items.map(\.name)), ["DerivedData", "Homebrew", "npm"])

        let system = state.groupResult(for: CleaningCategory.systemJunkGroup)
        XCTAssertEqual(system.totalSize, 300)
        XCTAssertEqual(system.itemCount, 1)
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
