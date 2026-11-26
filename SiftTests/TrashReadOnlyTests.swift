import XCTest
@testable import Sift

/// Owner decision: Sift never empties the Trash. The page stays a read-only
/// view of what is in it and tells the user to empty it in Finder.
@MainActor
final class TrashReadOnlyTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = fileManager.temporaryDirectory
            .appendingPathComponent("SiftTrashReadOnly-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(
            at: home.appendingPathComponent(".Trash", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let home { try? fileManager.removeItem(at: home) }
        try super.tearDownWithError()
    }

    /// There is no runtime seam for "this capability does not exist", so the
    /// test reads the app sources. It fails as soon as any of the old emptying
    /// plumbing (button id, AppState method, Finder script) comes back.
    func testNoAppSourceCanEmptyTheTrash() throws {
        let forbidden = [
            "emptyTrash",
            "isEmptyingTrash",
            "trashEmptier",
            "finderEmptyTrash",
            "category.emptyTrash",
            "tell application \"Finder\" to empty trash",
        ]
        var offenders: [String] = []
        for url in try appSourceFiles() {
            let source = try String(contentsOf: url, encoding: .utf8)
            for token in forbidden where source.contains(token) {
                offenders.append("\(url.lastPathComponent): \(token)")
            }
        }
        XCTAssertEqual(offenders, [], "Sift must have no way to empty the Trash")
    }

    func testCleaningTheTrashCategoryNeverRemovesAnything() async throws {
        let file = home.appendingPathComponent(".Trash/old.bin")
        try Data(repeating: 1, count: 8_192).write(to: file)
        let scanned = await ScanEngine(homeDirectory: home).scanCategory(.trash)
        let item = try XCTUnwrap(scanned.items.first { $0.name == "old.bin" })

        let state = AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false }),
            cleaningEngine: CleaningEngine(homeDirectory: home, isAppRunning: { _ in false }),
            historyStore: CleanupHistoryStore(fileURL: home.appendingPathComponent("history.json"))
        )
        state.categoryResults[.trash] = scanned

        state.cleanAll()
        try await waitUntil(timeout: 5) { !state.scanState.isActive }
        state.cleanCategory(.trash)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }
        await state.retryAfterFullDiskAccess(items: [item], context: .cleanup(failedCount: 1))

        XCTAssertTrue(fileManager.fileExists(atPath: file.path), "Sift never removes what is in the Trash")
        XCTAssertTrue(state.cleanupHistory.isEmpty)
    }

    func testAScheduledAutoCleanNeverTouchesTheTrash() async throws {
        let file = home.appendingPathComponent(".Trash/scheduled.bin")
        try Data(repeating: 2, count: 8_192).write(to: file)
        let state = AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false }),
            cleaningEngine: CleaningEngine(homeDirectory: home, isAppRunning: { _ in false }),
            historyStore: CleanupHistoryStore(fileURL: home.appendingPathComponent("history.json"))
        )
        var config = state.scheduler.config
        config.categoriesToScan = [.trash]
        config.autoClean = true
        config.notifyOnCompletion = false
        state.scheduler.config = config

        await state.runScheduledScan(isAppActive: false)

        XCTAssertTrue(fileManager.fileExists(atPath: file.path), "An unattended clean never empties the Trash")
        XCTAssertTrue(state.cleanupHistory.isEmpty)
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

    private func appSourceFiles() throws -> [URL] {
        let appDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sift", isDirectory: true)
        let enumerator = try XCTUnwrap(
            fileManager.enumerator(at: appDirectory, includingPropertiesForKeys: nil)
        )
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files
    }
}