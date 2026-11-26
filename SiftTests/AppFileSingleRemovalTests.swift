import AppKit
import XCTest
@testable import Sift

/// A row's "Remove this file" action goes through AppState so it cannot bypass
/// the running-app guard, and it must not replace the user's multi-selection.
@MainActor
final class AppFileSingleRemovalTests: XCTestCase {
    func testSingleRemovalRefusesTheBundleWhileTheAppIsRunning() {
        let app = makeApp()
        var trashed: [URL] = []
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                trashed = urls
                completion(urls, false, [], [])
            },
            isAppRunning: { _, _ in true }
        )
        state.selectedApp = app
        state.selectedFiles = [app.path]

        state.removeSingleFile(app.path)

        XCTAssertTrue(trashed.isEmpty, "A running app's bundle must not be moved to the Trash")
        XCTAssertNotNil(state.removalError)
        XCTAssertEqual(state.selectedFiles, [app.path])
    }

    func testSingleRemovalKeepsTheRestOfTheSelection() async {
        let a = URL(fileURLWithPath: "/fixtures/a")
        let b = URL(fileURLWithPath: "/fixtures/b")
        let c = URL(fileURLWithPath: "/fixtures/c")
        var trashed: [URL] = []
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                trashed = urls
                completion(urls, false, [], [])
            },
            isAppRunning: { _, _ in false }
        )
        state.discoveredFiles = [a, b, c]
        state.selectedFiles = [a, b, c]

        state.removeSingleFile(b)

        let expected: Set<URL> = [a, c]
        for _ in 0..<200 where state.selectedFiles != expected {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(trashed, [b])
        XCTAssertEqual(state.selectedFiles, expected)
        XCTAssertEqual(Set(state.discoveredFiles), expected)
    }


    func testBulkRemovalRefusesWhileTheAppIsRunning() {
        let app = makeApp()
        let support = URL(fileURLWithPath: "/Users/fixture/Library/Caches/com.fixture.app")
        var trashed: [URL] = []
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                trashed = urls
                completion(urls, false, [], [])
            },
            homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
            isAppRunning: { _, _ in true }
        )
        state.selectedApp = app
        state.selectedFiles = [app.path, support]

        state.removeSelectedFiles()

        XCTAssertTrue(trashed.isEmpty)
        XCTAssertNotNil(state.removalError)
        XCTAssertEqual(state.selectedFiles, [app.path, support])
    }

    func testRemovalSucceedsOnceTheAppQuits() {
        let app = makeApp()
        var running = true
        var trashed: [URL] = []
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                trashed = urls
                completion(urls, false, [], [])
            },
            isAppRunning: { _, _ in running }
        )
        state.selectedApp = app
        state.selectedFiles = [app.path]

        state.removeSingleFile(app.path)
        XCTAssertTrue(trashed.isEmpty)

        running = false
        state.removeSingleFile(app.path)
        XCTAssertEqual(trashed, [app.path])
    }

    // MARK: - Helpers

    private func makeApp() -> InstalledApp {
        InstalledApp(
            id: UUID(),
            appName: "Fixture",
            bundleIdentifier: "com.fixture.app",
            path: URL(fileURLWithPath: "/Applications/Fixture.app"),
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            size: 1
        )
    }
}