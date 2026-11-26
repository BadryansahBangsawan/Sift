import AppKit
import XCTest
@testable import Sift

/// The app-files scan and removal must not follow symlinked folders. A link
/// inside the fixture home can point at a fixture "Documents" directory, so
/// nothing here touches the real home or the Trash.
@MainActor
final class AppFileSymlinkSafetyTests: XCTestCase {
    private var fixtureHome: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        fixtureHome = fileManager.temporaryDirectory
            .appendingPathComponent("AppFileSymlinkSafety-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureHome { try? fileManager.removeItem(at: fixtureHome) }
    }

    func testOwnPathsInASharedVendorAreListedIndividually() async throws {
        let library = fixtureHome.appendingPathComponent("Library", isDirectory: true)
        let vendor = library.appendingPathComponent("Application Support/Vendor", isDirectory: true)
        let byName = vendor.appendingPathComponent("AStuff", isDirectory: true)
        let byBundle = vendor.appendingPathComponent("com.vendor.AStuff", isDirectory: true)
        try fileManager.createDirectory(at: byName, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: byBundle, withIntermediateDirectories: true)

        let finder = AppPathFinder(
            appInfo: AppPathFinder.AppInfo(
                appName: "AStuff",
                bundleIdentifier: "com.vendor.AStuff",
                path: fixtureHome.appendingPathComponent("Applications/AStuff.app"),
                entitlements: nil,
                teamIdentifier: nil
            ),
            locations: StubLocations(paths: [library.path]),
            homeDirectory: fixtureHome
        )

        let found = await scan(finder)

        XCTAssertFalse(found.contains { $0.standardizedFileURL.path == vendor.standardizedFileURL.path })
        XCTAssertTrue(found.contains { $0.standardizedFileURL.path == byName.standardizedFileURL.path })
        XCTAssertTrue(found.contains { $0.standardizedFileURL.path == byBundle.standardizedFileURL.path })
    }

    func testStandardLibrarySubfolderIsNeverReplacedByItsParent() async throws {
        let library = fixtureHome.appendingPathComponent("Library", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let ownCache = caches.appendingPathComponent("com.vendor.AStuff", isDirectory: true)
        try fileManager.createDirectory(at: ownCache, withIntermediateDirectories: true)

        let finder = AppPathFinder(
            appInfo: AppPathFinder.AppInfo(
                appName: "AStuff",
                bundleIdentifier: "com.vendor.AStuff",
                path: fixtureHome.appendingPathComponent("Applications/AStuff.app"),
                entitlements: nil,
                teamIdentifier: nil
            ),
            locations: StubLocations(paths: [library.path]),
            homeDirectory: fixtureHome
        )

        let found = await scan(finder)

        XCTAssertTrue(found.contains { $0.standardizedFileURL.path == ownCache.standardizedFileURL.path })
        XCTAssertFalse(found.contains { $0.standardizedFileURL.path == caches.standardizedFileURL.path })
    }

    func testSharedVendorFolderIsNotPromoted() async throws {
        let library = fixtureHome.appendingPathComponent("Library", isDirectory: true)
        let vendor = library.appendingPathComponent("Application Support/Vendor", isDirectory: true)
        let ownApp = vendor.appendingPathComponent("AStuff", isDirectory: true)
        let otherApp = vendor.appendingPathComponent("BStuff", isDirectory: true)
        try fileManager.createDirectory(at: ownApp, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: otherApp, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: ownApp.appendingPathComponent("data.txt"))
        try Data("b".utf8).write(to: otherApp.appendingPathComponent("data.txt"))

        let finder = AppPathFinder(
            appInfo: AppPathFinder.AppInfo(
                appName: "AStuff",
                bundleIdentifier: "com.vendor.AStuff",
                path: fixtureHome.appendingPathComponent("Applications/AStuff.app"),
                entitlements: nil,
                teamIdentifier: nil
            ),
            locations: StubLocations(paths: [library.path]),
            homeDirectory: fixtureHome
        )

        let found = await scan(finder)

        XCTAssertFalse(
            found.contains { $0.standardizedFileURL.path == vendor.standardizedFileURL.path },
            "the shared vendor folder holds another installed app's data"
        )
        XCTAssertFalse(
            found.contains { $0.standardizedFileURL.path == otherApp.standardizedFileURL.path },
            "another app's folder is not this app's leftover"
        )
    }

    func testAppFileScanDoesNotDescendIntoSymlinkedFolder() async throws {
        let fixture = try makeSymlinkFixture()
        let finder = AppPathFinder(
            appInfo: AppPathFinder.AppInfo(
                appName: "Fixture",
                bundleIdentifier: "com.fixture.app",
                path: fixtureHome.appendingPathComponent("Applications/Fixture.app"),
                entitlements: nil,
                teamIdentifier: nil
            ),
            locations: StubLocations(paths: [fixture.supportRoot.path])
        )

        let found = await scan(finder)

        XCTAssertFalse(
            found.contains { $0.path == fixture.taintedFile.path },
            "Scan followed the symlinked folder and listed a file outside the app's support directory"
        )
    }

    func testRemovalRefusesAPathThroughASymlinkedFolder() throws {
        let fixture = try makeSymlinkFixture()
        var trashed: [URL] = []
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                trashed = urls
                completion([], false, [], [])
            },
            homeDirectory: fixtureHome
        )
        state.selectedFiles = [fixture.taintedFile]

        state.removeSelectedFiles()

        XCTAssertTrue(trashed.isEmpty, "trashItem would follow the intermediate symlink")
        XCTAssertNotNil(state.removalError)
        XCTAssertFalse(state.selectedFiles.contains(fixture.taintedFile))
    }


    func testScanListsAMatchingSymlinkWithoutItsTargetContents() async throws {
        let fixture = try makeSymlinkFixture(linkName: "Fixture")
        let finder = AppPathFinder(
            appInfo: AppPathFinder.AppInfo(
                appName: "Fixture",
                bundleIdentifier: "com.fixture.app",
                path: fixtureHome.appendingPathComponent("Applications/Fixture.app"),
                entitlements: nil,
                teamIdentifier: nil
            ),
            locations: StubLocations(paths: [fixture.supportRoot.path])
        )

        let found = await scan(finder)

        XCTAssertTrue(found.contains { $0.path == fixture.linkedFolder.path })
        XCTAssertFalse(found.contains { $0.path == fixture.taintedFile.path })
    }

    func testRemovalAllowsTheSymlinkItself() throws {
        let fixture = try makeSymlinkFixture()
        var trashed: [URL] = []
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                trashed = urls
                completion(urls, false, [], [])
            },
            homeDirectory: fixtureHome
        )
        state.selectedFiles = [fixture.linkedFolder]

        state.removeSelectedFiles()

        XCTAssertEqual(trashed, [fixture.linkedFolder])
        XCTAssertNil(state.removalError)
    }

    func testRemovalRefusesANestedPathThroughASymlink() throws {
        let fixture = try makeSymlinkFixture()
        let nested = fixture.linkedFolder.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("fixture-cache.db"))

        var trashed: [URL] = []
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                trashed = urls
                completion([], false, [], [])
            },
            homeDirectory: fixtureHome
        )
        state.selectedFiles = [nested.appendingPathComponent("fixture-cache.db")]

        state.removeSelectedFiles()

        XCTAssertTrue(trashed.isEmpty)
        XCTAssertNotNil(state.removalError)
    }

    // MARK: - Helpers

    private struct SymlinkFixture {
        let supportRoot: URL
        let linkedFolder: URL
        let taintedFile: URL
    }

    private func makeSymlinkFixture(linkName: String = "SharedData") throws -> SymlinkFixture {
        let supportRoot = fixtureHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let documents = fixtureHome.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)

        let linkedFolder = supportRoot.appendingPathComponent(linkName)
        try fileManager.createSymbolicLink(at: linkedFolder, withDestinationURL: documents)
        try Data("fixture".utf8).write(to: documents.appendingPathComponent("fixture-cache.db"))

        return SymlinkFixture(
            supportRoot: supportRoot,
            linkedFolder: linkedFolder,
            taintedFile: linkedFolder.appendingPathComponent("fixture-cache.db")
        )
    }

    private func scan(_ finder: AppPathFinder) async -> Set<URL> {
        await withCheckedContinuation { continuation in
            finder.findPathsAsync { urls in
                continuation.resume(returning: urls)
            }
        }
    }
}

private final class StubLocations: Locations {
    init(paths: [String]) {
        super.init()
        appSearch = SearchCategory(name: "Apps", paths: paths)
    }
}