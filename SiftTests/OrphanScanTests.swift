import AppKit
import XCTest
@testable import Sift

/// The orphan scan compares reverse-search folders against the installed apps.
/// That list is filled in the background at launch, so a scan that trusts an
/// empty list reports every app's data as leftover — 44 orphan rows on a clean
/// machine instead of 20.
@MainActor
final class OrphanScanTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        // The safety policy only accepts volatile Library folders, so the scan
        // fixture has to sit under ~/Library/Caches like a real leftover.
        root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/PureMac-Orphans-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root, fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
    }

    func testAllowedOrphanIsStillRemovedAndLogged() throws {
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("SiftOrphanAllowed-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let trash = fileManager.temporaryDirectory
            .appendingPathComponent("SiftOrphanTrash-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: folder)
            try? fileManager.removeItem(at: trash)
        }

        let logFile = fileManager.temporaryDirectory
            .appendingPathComponent("orphan-allowed-log-\(UUID().uuidString)")
        let log = CleanupLog(fileURL: logFile, version: "4.2.0", build: "1")
        let outcome = OrphanRemover.remove(
            folder,
            log: log,
            isSafe: { _ in true },
            isExcluded: { _ in false },
            trash: { url in
                try FileManager.default.moveItem(
                    at: url,
                    to: trash.appendingPathComponent(url.lastPathComponent)
                )
            }
        )

        XCTAssertEqual(outcome, .removed)
        let line = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertTrue(line.contains("\"action\":\"trashed\""), line)
    }

    func testOrphanRemovalRefusesAnExcludedPath() throws {
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("SiftOrphanExcluded-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: folder) }

        let saved = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: CleanupExclusions.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
            }
        }
        CleanupExclusions.add(folder.path)

        let log = CleanupLog(
            fileURL: fileManager.temporaryDirectory.appendingPathComponent("orphan-log-\(UUID().uuidString)"),
            version: "4.2.0",
            build: "1"
        )
        var trashed: [URL] = []
        _ = OrphanRemover.remove(
            folder,
            log: log,
            isSafe: { _ in true },
            trash: { trashed.append($0) }
        )

        XCTAssertTrue(trashed.isEmpty, "an excluded orphan must never be moved to the Trash")
        XCTAssertTrue(fileManager.fileExists(atPath: folder.path))
    }

    func testOrphanAdminOutcomeDoesNotClaimAnExcludedPath() throws {
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("SiftOrphanExcludedAdmin-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: folder) }

        let saved = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: CleanupExclusions.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
            }
        }
        CleanupExclusions.add(folder.path)

        let logFile = fileManager.temporaryDirectory
            .appendingPathComponent("orphan-admin-log-\(UUID().uuidString)")
        let log = CleanupLog(fileURL: logFile, version: "4.2.0", build: "1")
        try fileManager.removeItem(at: folder) // simulate the admin batch deleting it
        OrphanRemover.recordAdminOutcome(urls: [folder], succeeded: true, log: log)

        let line = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertFalse(
            line.contains("\"action\":\"removedWithAdmin\""),
            "an excluded path must not be reported as removed by the admin batch"
        )
    }

    func testNoOrphansAreReportedWhenTheInstalledAppListIsEmpty() async throws {
        let folder = root.appendingPathComponent("com.example.kitchen", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let state = makeState(installedApps: [], reverseSearch: [root.path])
        state.findOrphans()
        await waitForOrphanScan(state)

        XCTAssertTrue(
            state.orphanedFiles.isEmpty,
            "Without the app list every folder looks orphaned; the scan must wait for it: \(state.orphanedFiles.map(\.lastPathComponent))"
        )
        XCTAssertTrue(state.orphanScanNeedsAppList, "The page must say why nothing was scanned")
        XCTAssertTrue(state.orphanScanCompleted)

    }

    func testDataOfAnInstalledAppIsNotAnOrphan() async throws {
        let installed = root.appendingPathComponent("com.example.kitchen", isDirectory: true)
        let leftover = root.appendingPathComponent("com.example.goneapp", isDirectory: true)
        for folder in [installed, leftover] {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        let state = makeState(
            installedApps: [installedApp(identifier: "com.example.kitchen")],
            reverseSearch: [root.path]
        )
        state.findOrphans()
        await waitForOrphanScan(state)

        XCTAssertEqual(state.orphanedFiles.map(\.lastPathComponent), ["com.example.goneapp"])
        XCTAssertFalse(state.orphanScanNeedsAppList)
        XCTAssertTrue(state.orphanScanCompleted)

    }

    // MARK: - Fixtures

    private func makeState(installedApps: [InstalledApp], reverseSearch: [String]) -> AppState {
        let locations = Locations()
        locations.reverseSearch.paths = reverseSearch
        return AppState(
            performStartupTasks: false,
            locationsProvider: { locations },
            historyStore: CleanupHistoryStore(fileURL: root.appendingPathComponent("history.json")),
            installedAppsProvider: { installedApps }
        )
    }

    private func installedApp(identifier: String) -> InstalledApp {
        InstalledApp(
            id: UUID(),
            appName: identifier,
            bundleIdentifier: identifier,
            path: URL(fileURLWithPath: "/Applications/\(identifier).app"),
            icon: NSImage(),
            size: 1_024
        )
    }

    private func waitForOrphanScan(_ state: AppState, timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !state.isSearchingOrphans { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Orphan scan did not finish")
    }
}
