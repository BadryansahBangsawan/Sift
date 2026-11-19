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
    private var savedSchedule: Data?
    private var savedThreshold: Any?

    private let mb: Int64 = 1024 * 1024

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedExclusions = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        savedSchedule = UserDefaults.standard.data(forKey: "PureMac.ScheduleConfig")
        savedThreshold = UserDefaults.standard.object(forKey: "settings.cleaning.largeFileThreshold")
        UserDefaults.standard.set(1, forKey: "settings.cleaning.largeFileThreshold")
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
        if let savedSchedule {
            UserDefaults.standard.set(savedSchedule, forKey: "PureMac.ScheduleConfig")
        } else {
            UserDefaults.standard.removeObject(forKey: "PureMac.ScheduleConfig")
        }
        if let savedThreshold {
            UserDefaults.standard.set(savedThreshold, forKey: "settings.cleaning.largeFileThreshold")
        } else {
            UserDefaults.standard.removeObject(forKey: "settings.cleaning.largeFileThreshold")
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

    func testPersonalFilesAreReviewableButNeverJunk() {
        let state = makeState()
        state.categoryResults = [
            .largeFiles: result(.largeFiles, 200 * mb),
            .trash: result(.trash, 50 * mb),
        ]
        state.recomputeTotalJunkSize()

        XCTAssertEqual(state.totalJunkSize, 0, "Neither category is junk")
        XCTAssertEqual(state.personalFilesSize, 250 * mb)
        XCTAssertFalse(state.categoryResults.isEmpty, "The dashboard still has rows to show")
    }

    func testCleaningALargeFileKeepsItOutOfTheJunkTotal() async throws {
        let video = try createFile("Downloads/holiday.mov", size: 2_000_000)
        let state = makeState()
        let scan = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.largeFiles)
        state.categoryResults[.systemJunk] = result(.systemJunk, 10 * mb)
        state.categoryResults[.largeFiles] = scan
        state.recomputeTotalJunkSize()
        XCTAssertEqual(state.totalJunkSize, 10 * mb)

        let item = try XCTUnwrap(scan.items.first { $0.name == video.lastPathComponent })
        state.toggleItem(item)
        state.scanState = .completed
        state.cleanCategory(.largeFiles)
        for _ in 0..<200 where state.scanState != .cleaned {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(state.scanState, .cleaned)
        XCTAssertEqual(state.categoryResults[.largeFiles]?.items.count, 0)
        XCTAssertEqual(state.totalJunkSize, 10 * mb)
        XCTAssertEqual(state.personalFilesSize, 0)
        try? removeTrashedItems()
    }

    func testEmptyingTheTrashKeepsItOutOfTheJunkTotal() async throws {
        let trash = fixtureHome.appendingPathComponent(".Trash", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: trash.appendingPathComponent("old.bin"))

        let state = makeState(trashEmptier: { [trash, fileManager] in
            for entry in try! fileManager.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
                try? fileManager.removeItem(at: entry)
            }
            return nil
        })
        state.categoryResults[.systemJunk] = result(.systemJunk, 10 * mb)
        state.categoryResults[.trash] = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.trash)
        state.recomputeTotalJunkSize()
        XCTAssertEqual(state.totalJunkSize, 10 * mb)

        await state.emptyTrash()

        XCTAssertNil(state.cleanError)
        XCTAssertEqual(state.totalJunkSize, 10 * mb)
        XCTAssertEqual(state.personalFilesSize, 0)
    }

    func testAScheduledScanKeepsPersonalFilesOutOfTheJunkTotal() async throws {
        try createFile("Downloads/holiday.mov", size: 2_000_000)
        let state = makeState()
        var config = state.scheduler.config
        config.categoriesToScan = [.largeFiles]
        config.autoClean = false
        config.notifyOnCompletion = false
        state.scheduler.config = config

        await state.runScheduledScan(isAppActive: false)

        XCTAssertEqual(state.categoryResults[.largeFiles]?.items.count, 1)
        XCTAssertEqual(state.totalJunkSize, 0)
        XCTAssertGreaterThan(state.personalFilesSize, 0)
    }

    // MARK: - Fixtures

    private func makeState(trashEmptier: @escaping AppState.TrashEmptier = { nil }) -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: fixtureHome),
            cleaningEngine: CleaningEngine(homeDirectory: fixtureHome),
            historyStore: historyStore,
            trashEmptier: trashEmptier
        )
    }

    @discardableResult
    private func createFile(_ relative: String, size: Int) throws -> URL {
        let url = fixtureHome.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: size).write(to: url)
        return url
    }

    /// `CleaningEngine` trashes into the real user Trash; remove the fixture
    /// file so the test leaves nothing behind.
    private func removeTrashedItems() throws {
        let trash = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let entries = (try? fileManager.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        for entry in entries where entry.lastPathComponent.hasPrefix("holiday") {
            try? fileManager.removeItem(at: entry)
        }
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
