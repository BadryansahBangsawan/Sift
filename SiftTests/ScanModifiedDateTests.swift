import Foundation
import XCTest
@testable import Sift

/// Rows that point at a real folder must carry its modification date: without
/// it the Modified column shows "–" and the age filter cannot judge the row.
final class ScanModifiedDateTests: XCTestCase {
    private let fileManager = FileManager.default
    private var homeDirectory: URL!

    override func setUpWithError() throws {
        homeDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("PureMac-Modified-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let homeDirectory, fileManager.fileExists(atPath: homeDirectory.path) {
            try fileManager.removeItem(at: homeDirectory)
        }
    }

    func testFolderBackedDeveloperCacheRowsCarryTheirModificationDate() async throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let derivedData = try makeFolder("Library/Developer/Xcode/DerivedData/App-hash", modified: stamp)
        let brew = try makeFolder("Library/Caches/Homebrew/downloads", modified: stamp)
        let npm = try makeFolder(".npm/_cacache", modified: stamp)
        try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: derivedData.path)
        try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: brew.path)
        try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: npm.path)

        let engine = ScanEngine(homeDirectory: homeDirectory, tmpRoots: [], isAppRunning: { _ in false })
        let developerCaches = await engine.scanCategory(.xcodeJunk)
        let caches = await engine.scanCategory(.brewCache)
        let node = await engine.scanCategory(.nodeCache)

        let derivedRow = try XCTUnwrap(developerCaches.items.first { $0.path == homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData").path })
        XCTAssertNotNil(derivedRow.lastModified, "A row that exists on disk has a modified date")
        let brewRow = try XCTUnwrap(caches.items.first { $0.path == homeDirectory.appendingPathComponent("Library/Caches/Homebrew").path })
        XCTAssertNotNil(brewRow.lastModified)
        let nodeRow = try XCTUnwrap(node.items.first { $0.path == homeDirectory.appendingPathComponent(".npm").path })
        XCTAssertNotNil(nodeRow.lastModified)
    }

    func testVirtualActionRowsKeepNoModifiedDate() async throws {
        try makeFolder("Library/Developer/Xcode/DerivedData/App-hash", modified: Date())
        let engine = ScanEngine(homeDirectory: homeDirectory, tmpRoots: [], isAppRunning: { _ in false })

        let purgeable = await engine.scanCategory(.purgeableSpace)

        XCTAssertTrue(purgeable.items.allSatisfy { $0.isActionItem })
        XCTAssertTrue(purgeable.items.allSatisfy { $0.lastModified == nil }, "Nothing on disk to date")
    }

    func testTheDateIsTheFolderOwnNotItsParents() async throws {
        let appStamp = Date(timeIntervalSince1970: 1_700_000_000)
        let parentStamp = Date(timeIntervalSince1970: 1_600_000_000)
        _ = try makeFolder("Library/Developer/Xcode/DerivedData/App-hash", modified: appStamp)
        try fileManager.setAttributes(
            [.modificationDate: appStamp],
            ofItemAtPath: homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData").path
        )
        let parent = homeDirectory.appendingPathComponent("Library/Developer/Xcode")
        try fileManager.setAttributes([.modificationDate: parentStamp], ofItemAtPath: parent.path)

        let engine = ScanEngine(homeDirectory: homeDirectory, tmpRoots: [], isAppRunning: { _ in false })
        let result = await engine.scanCategory(.xcodeJunk)
        let row = try XCTUnwrap(result.items.first { $0.path == parent.appendingPathComponent("DerivedData").path })
        let date = try XCTUnwrap(row.lastModified)

        XCTAssertEqual(
            date.timeIntervalSince1970,
            appStamp.timeIntervalSince1970,
            accuracy: 2,
            "The row reports its own folder's date, not the parent's"
        )
    }

    // MARK: - Fixtures

    private func makeFolder(_ relative: String, modified: Date) throws -> URL {
        let url = homeDirectory.appendingPathComponent(relative, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: url.appendingPathComponent("blob.bin"))
        try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }
}
