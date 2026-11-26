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

    // MARK: - Helpers

    private struct SymlinkFixture {
        let supportRoot: URL
        let linkedFolder: URL
        let taintedFile: URL
    }

    private func makeSymlinkFixture() throws -> SymlinkFixture {
        let supportRoot = fixtureHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let documents = fixtureHome.appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(at: supportRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)

        let linkedFolder = supportRoot.appendingPathComponent("SharedData")
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