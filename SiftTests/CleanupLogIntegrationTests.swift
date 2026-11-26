import XCTest
@testable import Sift

/// The removal entry points must write one audit row per item, with the path
/// and the outcome, into an injectable log under a temp directory.
@MainActor
final class CleanupLogIntegrationTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!
    private var trash: URL!
    private var logFile: URL!
    private var log: CleanupLog!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = fileManager.temporaryDirectory
            .appendingPathComponent("SiftCleanupLog-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        trash = fileManager.temporaryDirectory
            .appendingPathComponent("SiftCleanupLogTrash-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        logFile = home.appendingPathComponent("cleanup.log")
        log = CleanupLog(fileURL: logFile, version: "4.2.0", build: "40")
    }

    override func tearDownWithError() throws {
        if let home { try? fileManager.removeItem(at: home) }
        if let trash { try? fileManager.removeItem(at: trash) }
        try super.tearDownWithError()
    }

    func testCleaningEngineLogsAnUnlink() async throws {
        let file = try makeFile("Library/Caches/com.example.app/blob.bin", bytes: 4_096)
        let item = makeItem(path: file.path, category: .userCache, movesToTrash: false)

        let result = await makeEngine().cleanItems([item]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 1)
        let records = try self.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].action, "removed")
        XCTAssertEqual(records[0].source, "manual")
        XCTAssertEqual(records[0].category, item.category.rawValue)
        XCTAssertEqual(records[0].path, file.path)
        XCTAssertEqual(records[0].bytes, 4_096)
    }

    func testCleaningEngineLogsATrashMoveWithItsSource() async throws {
        let file = try makeFile("Library/Caches/com.example.app/archive.bin", bytes: 2_048)
        let item = makeItem(path: file.path, category: .userCache, movesToTrash: true)

        let result = await makeEngine().cleanItems([item], logSource: "scheduled") { _ in }

        XCTAssertEqual(result.trashedSpace, 4_096)
        let records = try self.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].action, "trashed")
        XCTAssertEqual(records[0].source, "scheduled")
        XCTAssertEqual(records[0].bytes, 4_096)
        XCTAssertTrue(fileManager.fileExists(atPath: trash.appendingPathComponent("archive.bin").path))
    }

    func testCleaningEngineLogsAFailedTrashMoveWithTheReason() async throws {
        let file = try makeFile("Library/Caches/com.example.app/locked.bin", bytes: 512)
        let item = makeItem(path: file.path, category: .userCache, movesToTrash: true)
        let engine = CleaningEngine(
            homeDirectory: home,
            isAppRunning: { _ in false },
            trashOperation: { _ in
                throw NSError(
                    domain: "CleanupLogIntegrationTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "The Trash is full"]
                )
            },
            cleanupLog: log
        )

        let result = await engine.cleanItems([item]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 0)
        let records = try self.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].action, "failed")
        XCTAssertTrue(records[0].reason?.contains("The Trash is full") == true, records[0].reason ?? "nil")
        XCTAssertTrue(fileManager.fileExists(atPath: file.path))
    }

    func testCleaningEngineLogsADeliberateSkip() async throws {
        let file = try makeFile("Library/Caches/com.example.app/skip.bin", bytes: 1_024)
        let item = CleanableItem(
            name: "skip.bin",
            path: file.path,
            size: 1_024,
            category: .trash,
            isSelected: true,
            lastModified: nil
        )

        _ = await makeEngine().cleanItems([item]) { _ in }

        let records = try self.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].action, "skipped")
        XCTAssertEqual(records[0].path, file.path)
        XCTAssertFalse(records[0].reason?.isEmpty ?? true)
    }

    func testAppFileRemovalLogsTrashedAndFailedURLs() async throws {
        let removed = home.appendingPathComponent("Library/Caches/com.example.app", isDirectory: true)
        let failed = home.appendingPathComponent("Library/Caches/com.example.app.helper", isDirectory: true)
        try fileManager.createDirectory(at: removed, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: failed, withIntermediateDirectories: true)

        let state = AppState(
            performStartupTasks: false,
            appFileTrasher: { urls, completion in
                completion([removed], false, [], [failed])
            },
            cleaningEngine: CleaningEngine(homeDirectory: home, isAppRunning: { _ in false }),
            cleanupLog: log,
            homeDirectory: home
        )

        state.removeSelectedFiles(confirmedURLs: [removed, failed])
        try await waitUntil { !state.isRemovingAppFiles }

        let records = try self.records()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.map(\.source)), ["uninstall"])
        XCTAssertEqual(
            Set(records.map(\.action)),
            ["trashed", "failed"]
        )
        XCTAssertEqual(Set(records.map(\.path)), [removed.path, failed.path])
    }

    func testOrphanRemovalLogsTheTrashMove() throws {
        let url = home.appendingPathComponent("Library/Caches/com.example.orphan", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        let outcome = OrphanRemover.remove(
            url,
            log: log,
            isSafe: { _ in true },
            trash: { [trash, fileManager] url in
                let destination = try XCTUnwrap(trash).appendingPathComponent(url.lastPathComponent)
                try fileManager.moveItem(at: url, to: destination)
            }
        )

        XCTAssertEqual(outcome, .removed)
        let records = try records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].action, "trashed")
        XCTAssertEqual(records[0].source, "orphans")
        XCTAssertEqual(records[0].path, url.path)
    }

    func testOrphanFailureAndAdminOutcomeAreLogged() throws {
        let url = home.appendingPathComponent("Library/Caches/com.example.orphan", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        let outcome = OrphanRemover.remove(
            url,
            log: log,
            isSafe: { _ in true },
            trash: { _ in throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "denied"]) }
        )
        XCTAssertEqual(outcome, .failed)

        // The admin batch is simulated by deleting the path first.
        try fileManager.removeItem(at: url)
        OrphanRemover.recordAdminOutcome(urls: [url], succeeded: true, log: log)

        let records = try records()
        XCTAssertEqual(records.map(\.action), ["failed", "removedWithAdmin"])
        XCTAssertEqual(records[0].reason, "denied")
    }

    // MARK: - Fixtures

    private func makeEngine() -> CleaningEngine {
        CleaningEngine(
            homeDirectory: home,
            isAppRunning: { _ in false },
            trashOperation: { [trash, fileManager] url in
                let destination = try XCTUnwrap(trash).appendingPathComponent(url.lastPathComponent)
                try fileManager.moveItem(at: url, to: destination)
                return destination.path
            },
            cleanupLog: log
        )
    }

    private func makeItem(path: String, category: CleaningCategory, movesToTrash: Bool) -> CleanableItem {
        CleanableItem(
            name: (path as NSString).lastPathComponent,
            path: path,
            size: 4_096,
            category: category,
            isSelected: true,
            lastModified: nil,
            movesToTrash: movesToTrash
        )
    }

    @discardableResult
    private func makeFile(_ relative: String, bytes: Int) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    private func records() throws -> [CleanupLog.Record] {
        guard fileManager.fileExists(atPath: logFile.path) else { return [] }
        let lines = try String(contentsOf: logFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        return try lines.map { try JSONDecoder().decode(CleanupLog.Record.self, from: Data($0.utf8)) }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for removal to finish")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}