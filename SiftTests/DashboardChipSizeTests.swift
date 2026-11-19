import XCTest
@testable import Sift

final class DashboardChipSizeTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureHome = fileManager.temporaryDirectory
            .appendingPathComponent("DashboardChipSizeTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureHome { try? fileManager.removeItem(at: fixtureHome) }
        try super.tearDownWithError()
    }

    func testContainersSizeTotalsEveryContainer() async throws {
        let containers = fixtureHome.appendingPathComponent("Library/Containers", isDirectory: true)
        let first = containers.appendingPathComponent("com.example.one/Data/Library", isDirectory: true)
        let second = containers.appendingPathComponent("com.example.two/Data", isDirectory: true)
        try fileManager.createDirectory(at: first, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: second, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16_384).write(to: first.appendingPathComponent("db.sqlite"))
        try Data(repeating: 2, count: 8_192).write(to: second.appendingPathComponent(".hidden"))

        let size = await ScanEngine(homeDirectory: fixtureHome).containersSize()

        XCTAssertGreaterThanOrEqual(size, 16_384 + 8_192)
        XCTAssertLessThan(size, 16_384 + 8_192 + 64 * 1024)
    }

    func testPurgeableCategoryTotalMatchesTheRowsItLists() async {
        var info = DiskInfo()
        info.purgeableSpace = 5_000_000_000
        let engine = ScanEngine(
            homeDirectory: FileManager.default.temporaryDirectory,
            diskInfoProvider: { info }
        )

        let result = await engine.scanCategory(.purgeableSpace)

        XCTAssertEqual(result.items.count, 1, "The purge row is the only thing the purge reclaims")
        XCTAssertEqual(result.items.first?.name, "APFS Purgeable Space")
        XCTAssertEqual(result.items.first?.isSelected, true)
        XCTAssertEqual(result.totalSize, result.items.reduce(Int64(0)) { $0 + $1.size })
        XCTAssertEqual(result.totalSize, 5_000_000_000)
    }

    func testPurgeableCategoryIsEmptyWhenTheDiskReportsNone() async {
        let engine = ScanEngine(
            homeDirectory: FileManager.default.temporaryDirectory,
            diskInfoProvider: { DiskInfo() }
        )

        let result = await engine.scanCategory(.purgeableSpace)

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.totalSize, 0)
    }

    func testPurgeableRowNamesNoFilesystemPath() async {
        var info = DiskInfo()
        info.purgeableSpace = 12_000_000_000
        let engine = ScanEngine(
            homeDirectory: FileManager.default.temporaryDirectory,
            diskInfoProvider: { info }
        )

        let result = await engine.scanCategory(.purgeableSpace)

        let item = result.items.first
        XCTAssertEqual(item?.path, "", "The purge row must not point at / as a deletable path")
        XCTAssertEqual(item?.isActionItem, true, "An empty path marks the row as an action, not a file")
        XCTAssertEqual(result.totalSize, item?.size)
    }

    func testMissingContainersFolderMeasuresZero() async {
        let size = await ScanEngine(homeDirectory: fixtureHome).containersSize()
        XCTAssertEqual(size, 0)
    }

    func testUserCacheLeavesCachesOwnedByXcodeJunkAndAIToolsToThem() async throws {
        let caches = fixtureHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let ownedByOtherCategories = [
            "com.apple.dt.Xcode",
            "org.swift.swiftpm",
            "com.anthropic.claudefordesktop",
        ]
        for name in ownedByOtherCategories + ["com.example.ordinary"] {
            let folder = caches.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 0x11, count: 8_192).write(to: folder.appendingPathComponent("blob"))
        }

        let engine = ScanEngine(homeDirectory: fixtureHome)
        let userCache = await engine.scanCategory(.userCache)
        let paths = Set(userCache.items.map { $0.path })

        XCTAssertTrue(paths.contains(caches.appendingPathComponent("com.example.ordinary").path))
        for name in ownedByOtherCategories {
            XCTAssertFalse(
                paths.contains(caches.appendingPathComponent(name).path),
                "User Cache must not repeat the \(name) row another category owns"
            )
        }

        let xcodeJunk = await engine.scanCategory(.xcodeJunk)
        XCTAssertTrue(xcodeJunk.items.contains { $0.path == caches.appendingPathComponent("com.apple.dt.Xcode").path })
        XCTAssertTrue(xcodeJunk.items.contains { $0.path == caches.appendingPathComponent("org.swift.swiftpm").path })

        let aiApps = await engine.scanCategory(.aiApps)
        XCTAssertTrue(aiApps.items.contains { $0.path == caches.appendingPathComponent("com.anthropic.claudefordesktop").path })
    }

    func testUserCacheKeepsSiblingFoldersThatOnlyShareAClaimedRootPrefix() async throws {
        let caches = fixtureHome.appendingPathComponent("Library/Caches", isDirectory: true)
        let sibling = caches.appendingPathComponent("com.apple.dt.XcodeJunk", isDirectory: true)
        try fileManager.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data(repeating: 0x22, count: 8_192).write(to: sibling.appendingPathComponent("blob"))

        let userCache = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.userCache)

        XCTAssertTrue(
            userCache.items.contains { $0.path == sibling.path },
            "Only the exact claimed root belongs to another category; a look-alike sibling stays in User Cache"
        )
    }

    func testSystemJunkLeavesLogsTheAIToolsCategoryOwnsToIt() async throws {
        let logs = fixtureHome.appendingPathComponent("Library/Logs", isDirectory: true)
        let claudeLogs = logs.appendingPathComponent("Claude", isDirectory: true)
        let ordinaryLogs = logs.appendingPathComponent("com.example.app", isDirectory: true)
        for folder in [claudeLogs, ordinaryLogs] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 0x44, count: 8_192).write(to: folder.appendingPathComponent("out.log"))
        }
        let claimed = claudeLogs.resolvingSymlinksInPath().path
        let ordinary = ordinaryLogs.resolvingSymlinksInPath().path

        let engine = ScanEngine(homeDirectory: fixtureHome, tmpRoots: [])
        let aiApps = await engine.scanCategory(.aiApps)
        XCTAssertTrue(aiApps.items.contains { $0.path == claimed })

        let systemJunk = await engine.scanCategory(.systemJunk)
        let paths = Set(systemJunk.items.map { $0.path })
        XCTAssertTrue(paths.contains(ordinary), "Ordinary logs stay in System Junk")
        XCTAssertFalse(
            paths.contains(claimed),
            "System Junk must not repeat the Claude log folder the AI tools category owns"
        )
    }

    func testSystemJunkKeepsLogFoldersThatOnlyShareTheClaudePrefix() async throws {
        let logs = fixtureHome.appendingPathComponent("Library/Logs", isDirectory: true)
        let lookAlike = logs.appendingPathComponent("ClaudeHelper", isDirectory: true)
        try fileManager.createDirectory(at: lookAlike, withIntermediateDirectories: true)
        try Data(repeating: 0x55, count: 8_192).write(to: lookAlike.appendingPathComponent("out.log"))

        let systemJunk = await ScanEngine(homeDirectory: fixtureHome, tmpRoots: []).scanCategory(.systemJunk)

        XCTAssertTrue(
            systemJunk.items.contains { $0.path == lookAlike.resolvingSymlinksInPath().path },
            "Only the exact folder AI tools claims is left to it"
        )
    }

    func testSystemJunkTotalMatchesTheRowsItKeeps() async throws {
        let logs = fixtureHome.appendingPathComponent("Library/Logs", isDirectory: true)
        for name in ["Claude", "com.example.app"] {
            let folder = logs.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 0x66, count: 8_192).write(to: folder.appendingPathComponent("out.log"))
        }

        let systemJunk = await ScanEngine(homeDirectory: fixtureHome, tmpRoots: []).scanCategory(.systemJunk)

        XCTAssertEqual(
            systemJunk.totalSize,
            systemJunk.items.reduce(Int64(0)) { $0 + $1.size },
            "The category total must be the rows it lists"
        )
    }

    func testUserCacheTotalMatchesTheRowsItKeeps() async throws {
        let caches = fixtureHome.appendingPathComponent("Library/Caches", isDirectory: true)
        for name in ["com.apple.dt.Xcode", "com.example.ordinary", "com.example.second"] {
            let folder = caches.appendingPathComponent(name, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 0x33, count: 8_192).write(to: folder.appendingPathComponent("blob"))
        }

        let userCache = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.userCache)

        XCTAssertEqual(userCache.items.count, 2)
        XCTAssertEqual(userCache.totalSize, userCache.items.reduce(0) { $0 + $1.size })
        XCTAssertFalse(userCache.items.contains { $0.path == caches.appendingPathComponent("com.apple.dt.Xcode").path })
    }
}
