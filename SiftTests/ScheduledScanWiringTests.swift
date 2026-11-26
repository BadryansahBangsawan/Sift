import XCTest
@testable import Sift

/// The scheduled scan is the unattended path. When auto-clean is on, the clean
/// it starts has to run in unattended (Trash) mode, not as a watched unlink.
@MainActor
final class ScheduledScanWiringTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!
    private var trash: URL!
    private var historyStore: CleanupHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = fileManager.temporaryDirectory
            .appendingPathComponent("SiftScheduledWiring-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        trash = fileManager.temporaryDirectory
            .appendingPathComponent("SiftScheduledWiringTrash-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        historyStore = CleanupHistoryStore(fileURL: home.appendingPathComponent("history.json"))
    }

    override func tearDownWithError() throws {
        if let home { try? fileManager.removeItem(at: home) }
        if let trash { try? fileManager.removeItem(at: trash) }
        try super.tearDownWithError()
    }

    func testAutoCleanRunUsesUnattendedTrashMode() async throws {
        let cache = home.appendingPathComponent("Library/Caches/com.example.app", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8_192).write(to: cache.appendingPathComponent("blob.bin"))

        let state = AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false }),
            cleaningEngine: CleaningEngine(
                homeDirectory: home,
                isAppRunning: { _ in false },
                trashOperation: { [trash, fileManager] url in
                    let destination = try XCTUnwrap(trash).appendingPathComponent(url.lastPathComponent)
                    try fileManager.moveItem(at: url, to: destination)
                    return destination.path
                }
            ),
            historyStore: historyStore
        )
        var config = state.scheduler.config
        config.categoriesToScan = [.userCache]
        config.autoClean = true
        config.minimumCleanSize = 1
        config.notifyOnCompletion = false
        state.scheduler.config = config

        await state.runScheduledScan(isAppActive: false)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertFalse(
            fileManager.fileExists(atPath: cache.path),
            "the scheduled clean removed the cache from its folder"
        )
        XCTAssertTrue(
            fileManager.fileExists(atPath: trash.appendingPathComponent("com.example.app").path),
            "the scheduled clean must use Trash mode, not unlink"
        )
        let record = try XCTUnwrap(state.cleanupHistory.first)
        XCTAssertEqual(record.source, .scheduled)
        XCTAssertEqual(record.freedBytes, 0)
        XCTAssertGreaterThan(record.trashedBytes, 0)
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
}