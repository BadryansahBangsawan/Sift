import AppKit
import Combine
import XCTest
@testable import Sift

@MainActor
final class AppStateTests: XCTestCase {
    func testScanForAppFilesTracksLocationsWhileResultsArePending() throws {
        var completion: ((Set<URL>) -> Void)?
        let expectedLocations = ["/one", "/two", "/three"]
        let appState = AppState(
            performStartupTasks: false,
            locationsProvider: {
                StubLocations(paths: expectedLocations)
            },
            appFileScanner: { _, locations, pendingCompletion in
                XCTAssertEqual(locations.appSearch.paths, expectedLocations)
                completion = pendingCompletion
            }
        )

        appState.scanForAppFiles(makeApp())

        XCTAssertTrue(appState.isScanningAppFiles)
        XCTAssertTrue(appState.discoveredFiles.isEmpty)
        XCTAssertEqual(appState.currentAppFileSearchLocationCount, expectedLocations.count)

        let pendingCompletion = try XCTUnwrap(completion)
        let urls: Set<URL> = [
            URL(fileURLWithPath: "/tmp/B"),
            URL(fileURLWithPath: "/tmp/A")
        ]

        pendingCompletion(urls)

        XCTAssertFalse(appState.isScanningAppFiles)
        XCTAssertEqual(
            appState.discoveredFiles,
            urls.sorted { $0.path < $1.path }
        )
        XCTAssertEqual(appState.selectedFiles, urls)
        XCTAssertEqual(appState.currentAppFileSearchLocationCount, urls.count)
    }

    func testOlderAppScanCannotReplaceNewerAppResults() {
        var completions: [((Set<URL>) -> Void)] = []
        let state = AppState(performStartupTasks: false, appFileScanner: { _, _, completion in
            completions.append(completion)
        })
        state.scanForAppFiles(makeApp())
        state.scanForAppFiles(makeApp())
        let latest: Set<URL> = [URL(fileURLWithPath: "/fixtures/latest")]
        completions[1](latest)
        completions[0]([URL(fileURLWithPath: "/fixtures/stale")])
        XCTAssertEqual(Set(state.discoveredFiles), latest)
        XCTAssertEqual(state.selectedFiles, latest)
    }

    func testFullDiskAccessRetryKeepsUninstallInTrashFlow() async {
        let expectedURLs: Set<URL> = [
            URL(fileURLWithPath: "/Applications/Fixture.app"),
            URL(fileURLWithPath: "/Users/fixture/Library/Containers/com.fixture.app")
        ]
        var receivedURLs: Set<URL> = []
        let invoked = expectation(description: "app file trasher")
        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                receivedURLs = Set(urls)
                completion(urls, false, [], [])
                invoked.fulfill()
            }
        )
        let items = expectedURLs.map {
            CleanableItem(
                name: $0.lastPathComponent,
                path: $0.path,
                size: 100,
                category: .systemJunk,
                isSelected: true,
                lastModified: nil
            )
        }

        await state.retryAfterFullDiskAccess(
            items: items,
            context: .uninstall(appName: "Fixture", failedCount: items.count)
        )
        await fulfillment(of: [invoked], timeout: 1)

        XCTAssertEqual(receivedURLs, expectedURLs)
    }

    func testVisibleSelectionPreservesHiddenRowsAndManualDefaults() {
        let state = AppState(performStartupTasks: false)
        let visible = cleanupItem(selected: false)
        let hidden = cleanupItem(selected: true)
        state.categoryResults[.userCache] = CategoryResult(category: .userCache, items: [visible, hidden], totalSize: 200)
        state.setSelection(true, for: [visible])
        XCTAssertTrue(state.isItemSelected(visible))
        XCTAssertTrue(state.isItemSelected(hidden))
        state.setSelection(false, for: [visible])
        XCTAssertFalse(state.isItemSelected(visible))
        XCTAssertTrue(state.isItemSelected(hidden))
    }

    func testScheduledScanWaitsForReviewToLeaveForeground() {
        let state = AppState(performStartupTasks: false)
        let item = cleanupItem(selected: true)
        state.categoryResults[.userCache] = CategoryResult(category: .userCache, items: [item], totalSize: 100)
        state.scanState = .completed
        XCTAssertFalse(state.canRunScheduledScan(isAppActive: true))
        XCTAssertTrue(state.canRunScheduledScan(isAppActive: false))
        state.showCleanConfirmation = true
        XCTAssertFalse(state.canRunScheduledScan(isAppActive: false))
        XCTAssertEqual(state.categoryResults[.userCache]?.items.map(\.id), [item.id])
        XCTAssertEqual(state.scanState, .completed)
    }

    func testManagedDerivedDataRequiresManualSelectionEvenForScheduledCleanup() throws {
        let state = AppState(performStartupTasks: false)
        let managedRoot = try XCTUnwrap(XcodeBuildMCPDerivedDataSupport.managedRoots().first)
        let item = CleanableItem(
            name: "XcodeBuildMCP: Fixture",
            path: managedRoot
                .appendingPathComponent("workspaces/Fixture-\(UUID().uuidString)/DerivedData").path,
            size: 4_096,
            category: .xcodeJunk,
            isSelected: false,
            lastModified: .distantPast
        )
        state.categoryResults[.xcodeJunk] = CategoryResult(category: .xcodeJunk, items: [item], totalSize: item.size)
        state.scanState = .completed

        XCTAssertFalse(state.isItemSelected(item))
        XCTAssertEqual(state.totalSelectedSize, 0)
        state.cleanAll()
        XCTAssertEqual(state.scanState, .completed)
        state.cleanAll(scheduled: true)
        XCTAssertEqual(state.scanState, .completed)
        XCTAssertEqual(state.categoryResults[.xcodeJunk]?.items.map(\.id), [item.id])

        state.toggleItem(item)
        XCTAssertTrue(state.isItemSelected(item))
        XCTAssertEqual(state.totalSelectedSize, item.size)
        state.toggleItem(item)
        XCTAssertFalse(state.isItemSelected(item))
    }

    func testScheduledScanWaitsForActiveOperations() {
        let state = AppState(performStartupTasks: false)
        state.scanState = .cleaning(progress: 0.2)
        XCTAssertFalse(state.canRunScheduledScan(isAppActive: false))
        state.scanState = .idle
        state.isRemovingAppFiles = true
        XCTAssertFalse(state.canRunScheduledScan(isAppActive: false))
    }

    func testStopScanPreservesCompletedResultsAndDoesNotStopCleaning() {
        let state = AppState(performStartupTasks: false)
        state.categoryResults[.userCache] = CategoryResult(category: .userCache, items: [cleanupItem(selected: true)], totalSize: 100)
        state.scanState = .scanning(progress: 0.5, currentCategory: "User Cache")
        state.cancelScan()
        XCTAssertTrue(state.scanWasCancelled)
        XCTAssertEqual(state.scanState, .completed)
        XCTAssertEqual(state.totalItemCount, 1)
        state.scanState = .cleaning(progress: 0.5)
        state.cancelScan()
        XCTAssertEqual(state.scanState, .cleaning(progress: 0.5))
    }

    private func cleanupItem(selected: Bool) -> CleanableItem {
        CleanableItem(name: "Fixture", path: "/fixtures/\(UUID().uuidString)", size: 100, category: .userCache, isSelected: selected, lastModified: nil)
    }

    func testCleaningManyJunkItemsDoesNotFloodTheMainThreadWithProgressUpdates() async throws {
        let itemCount = 3000
        let home = try makeUserCacheFixture(itemCount: itemCount)
        defer { try? FileManager.default.removeItem(at: home) }

        let state = AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: home),
            cleaningEngine: CleaningEngine(homeDirectory: home),
            historyStore: CleanupHistoryStore(fileURL: home.appendingPathComponent("history.json"))
        )

        state.scanSingleCategory(.userCache)
        try await waitUntil(timeout: 60) { state.scanState == .completed }
        XCTAssertEqual(state.categoryResults[.userCache]?.items.count, itemCount)
        XCTAssertTrue(state.categoryResults[.userCache]?.items.allSatisfy(\.isSelected) == true)

        // Every assignment to scanState publishes, and each publication
        // invalidates the whole window. Thousands of them while one cleanup
        // runs are what the user feels as a freeze.
        let publications = PublicationCounter()
        let cancellable = state.$scanState.dropFirst().sink { _ in publications.increment() }
        defer { withExtendedLifetime(cancellable) {} }

        let probe = MainThreadProbe()
        probe.start()
        let cleanStarted = Date()
        state.cleanAll()
        try await waitUntil(timeout: 120) { !state.scanState.isActive }
        let cleanSeconds = Date().timeIntervalSince(cleanStarted)
        probe.stop()

        print(
            "[PERF] clean of \(itemCount) rows: \(String(format: "%.3f", cleanSeconds))s, "
                + "\(publications.count) scanState publications, "
                + "largest main-thread gap \(String(format: "%.1f", probe.maxGapMilliseconds))ms"
        )
        XCTAssertGreaterThan(state.totalFreedSpace, 0)
        XCTAssertEqual(state.cleanupHistory.first?.freedBytes, state.totalFreedSpace)
        XCTAssertLessThanOrEqual(
            publications.count,
            150,
            "Cleaning \(itemCount) rows republished scanState \(publications.count) times, one full window redraw each"
        )
        // A loose ceiling: this environment shares the machine with other
        // builds, so a few hundred ms of scheduler noise is not the bug. A
        // genuinely blocked window (the ~4 s freeze users reported) trips it.
        XCTAssertLessThanOrEqual(
            probe.maxGapMilliseconds,
            1_000,
            "The window froze for \(Int(probe.maxGapMilliseconds))ms while cleaning \(itemCount) rows"
        )
    }

    private func makeUserCacheFixture(itemCount: Int) throws -> URL {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("SiftCleanPerf-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        for index in 0..<itemCount {
            let folder = caches.appendingPathComponent(String(format: "com.example.row%04d", index), isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 0x5A, count: 4_096).write(to: folder.appendingPathComponent("blob"))
        }
        return home
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out after \(Int(timeout))s waiting for the cleanup to finish")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeApp() -> InstalledApp {
        InstalledApp(
            id: UUID(),
            appName: "PureMac",
            bundleIdentifier: "com.puremac.app",
            path: URL(fileURLWithPath: "/Applications/PureMac.app"),
            icon: NSImage(size: NSSize(width: 32, height: 32)),
            size: 1
        )
    }
}

private final class StubLocations: Locations {
    init(paths: [String]) {
        super.init()
        appSearch = SearchCategory(name: "Apps", paths: paths)
    }
}


private final class PublicationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Measures how long the main actor is ever unavailable while a cleanup runs.
/// Each round trip records the time between asking for the main actor and
/// getting it, so a multi-second stall anywhere in the clean shows up as a
/// large gap. Used by the cleanup responsiveness test.
private final class MainThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var maxGap: Double = 0
    private var task: Task<Void, Never>?

    func start() {
        task = Task.detached(priority: .high) { [self] in
            while !isStopped {
                let started = ContinuousClock.now
                await MainActor.run {}
                let gap = started.duration(to: .now)
                let milliseconds = Double(gap.components.seconds) * 1000
                    + Double(gap.components.attoseconds) / 1_000_000_000_000_000
                lock.lock()
                if milliseconds > maxGap { maxGap = milliseconds }
                lock.unlock()
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        task?.cancel()
        task = nil
    }

    var maxGapMilliseconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return maxGap
    }
}
