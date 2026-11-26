import XCTest
@testable import Sift

/// Work the app hands to a provider closure must not run on the main actor:
/// the closure walks the file system or lists installed apps, which takes
/// seconds and freezes the window if it runs where the UI draws.
@MainActor
final class ProviderThreadTests: XCTestCase {
    func testLeftoverScanCallsTheAppListProviderOffTheMainThread() async throws {
        let probe = ProviderProbe()
        let state = await MainActor.run {
            AppState(performStartupTasks: false, installedAppsProvider: { probe.record() })
        }

        state.findOrphans()
        for _ in 0..<200 {
            if state.orphanScanCompleted { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(probe.calls, 1, "The scan fetches the app list itself when it has none")
        XCTAssertFalse(probe.onMainThread, "Listing every installed app on the main actor freezes the window")
    }

    func testLeftoverScanBuildsItsSearchPathsOffTheMainThread() async throws {
        let probe = ProviderProbe()
        let state = await MainActor.run {
            AppState(
                performStartupTasks: false,
                locationsProvider: { probe.recordLocations() },
                installedAppsProvider: { probe.record() }
            )
        }

        state.findOrphans()
        for _ in 0..<200 {
            if state.orphanScanCompleted { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertEqual(probe.locationCalls, 1)
        XCTAssertFalse(probe.locationsOnMainThread, "Building the search paths reads the disk; keep it off the main actor")
    }
}

/// Records who ran the provider and where.
final class ProviderProbe {
    private(set) var calls = 0
    private(set) var onMainThread = true

    private(set) var locationCalls = 0
    private(set) var locationsOnMainThread = true

    func record() -> [InstalledApp] {
        calls += 1
        onMainThread = Thread.isMainThread
        return []
    }

    func recordLocations() -> Locations {
        locationCalls += 1
        locationsOnMainThread = Thread.isMainThread
        return Locations()
    }
}
