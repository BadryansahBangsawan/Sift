import AppKit
import XCTest
@testable import Sift

/// `findOrphans` has no generation token. A slow first scan can finish after a
/// newer scan and overwrite the newer outcome, so the page reports "couldn't
/// compare installed apps" even though the second scan had the app list.
@MainActor
final class OrphanScanGenerationTests: XCTestCase {
    func testNewerOrphanScanOutcomeSurvivesAnOlderFinishingScan() async throws {
        let gate = ProviderGate()
        let state = AppState(
            performStartupTasks: false,
            locationsProvider: { StubLocations(paths: []) },
            installedAppsProvider: { gate.installedApps() }
        )

        state.findOrphans()
        try await waitUntil(timeout: 5) { gate.firstCallStarted }

        state.findOrphans()
        try await waitUntil(timeout: 5) { !state.orphanScanNeedsAppList && state.orphanScanCompleted }

        gate.releaseFirstCall()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(
            state.orphanScanNeedsAppList,
            "A stale scan overwrote the newer scan's app-list result"
        )
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for the second orphan scan")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testSpinnerStopsOnlyWithTheNewestScanAndTheOldOneWritesNothing() async throws {
        let gate = ProviderGate()
        let state = AppState(
            performStartupTasks: false,
            locationsProvider: { StubLocations(paths: []) },
            installedAppsProvider: { gate.installedApps() }
        )

        state.findOrphans()
        try await waitUntil(timeout: 5) { gate.firstCallStarted }

        state.findOrphans()
        try await waitUntil(timeout: 5) { !state.isSearchingOrphans && state.orphanScanCompleted }
        XCTAssertFalse(state.orphanScanNeedsAppList, "The newest scan had the app list")

        gate.releaseFirstCall()
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertFalse(state.isSearchingOrphans, "A cancelled scan must not leave the spinner on")
        XCTAssertFalse(state.orphanScanNeedsAppList, "A cancelled scan must not write its outcome")
        XCTAssertTrue(state.orphanScanCompleted)
    }
}

private final class ProviderGate: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var blocked = false
    private let release = DispatchSemaphore(value: 0)

    var firstCallStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return calls >= 1 && blocked
    }

    func releaseFirstCall() {
        release.signal()
    }

    func installedApps() -> [InstalledApp] {
        lock.lock()
        calls += 1
        let index = calls
        lock.unlock()
        if index == 1 {
            lock.lock()
            blocked = true
            lock.unlock()
            release.wait()
            return []
        }
        return [
            InstalledApp(
                id: UUID(),
                appName: "Known",
                bundleIdentifier: "com.known.app",
                path: URL(fileURLWithPath: "/Applications/Known.app"),
                icon: NSImage(size: NSSize(width: 16, height: 16)),
                size: 1
            )
        ]
    }
}

private final class StubLocations: Locations {
    init(paths: [String]) {
        super.init()
        appSearch = SearchCategory(name: "Apps", paths: paths)
        reverseSearch = SearchCategory(name: "Reverse", paths: paths)
    }

}
