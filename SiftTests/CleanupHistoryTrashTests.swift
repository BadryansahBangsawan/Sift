import XCTest
@testable import Sift

/// Moving a file to the Trash changes what the user has, so the cleanup
/// history must record the row even though it frees no space yet. The category
/// page and the Full Disk Access retry must behave like `cleanAll`.
@MainActor
final class CleanupHistoryTrashTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!
    private var trash: URL!
    private var historyStore: CleanupHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = fileManager.temporaryDirectory
            .appendingPathComponent("SiftCleanupHistory-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        trash = fileManager.temporaryDirectory
            .appendingPathComponent("SiftCleanupHistoryTrash-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        historyStore = CleanupHistoryStore(fileURL: home.appendingPathComponent("history.json"))
    }

    override func tearDownWithError() throws {
        if let home { try? fileManager.removeItem(at: home) }
        if let trash { try? fileManager.removeItem(at: trash) }
        try super.tearDownWithError()
    }

    func testCleaningALargeFileFromItsPageRecordsTrashedHistory() async throws {
        let file = try makeFile("Downloads/holiday.mov", size: 2_000_000)
        let item = trashedItem(named: file.lastPathComponent, path: file.path, size: 2_000_000, category: .largeFiles)
        let state = makeState()
        state.categoryResults[.largeFiles] = CategoryResult(
            category: .largeFiles,
            items: [item],
            totalSize: item.size
        )

        state.cleanCategory(.largeFiles)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        let record = try XCTUnwrap(
            state.cleanupHistory.first,
            "A Trash-only clean still changed the user's files: it needs a history row"
        )
        XCTAssertEqual(record.freedBytes, 0, "Bytes in the Trash are not freed space")
        XCTAssertEqual(record.trashedBytes, item.size)
        XCTAssertEqual(record.category, .largeFiles)
        XCTAssertEqual(historyStore.load().first?.trashedBytes, item.size)
    }

    func testRetryingALargeFileTrashMoveRecordsHistory() async throws {
        let file = try makeFile("Downloads/retry.mov", size: 1_000_000)
        let item = trashedItem(named: file.lastPathComponent, path: file.path, size: 1_000_000, category: .largeFiles)
        let state = makeState()

        await state.retryAfterFullDiskAccess(items: [item], context: .cleanup(failedCount: 1))

        let record = try XCTUnwrap(state.cleanupHistory.first, "The retry trashed the file and must say so")
        XCTAssertEqual(record.freedBytes, 0)
        XCTAssertEqual(record.trashedBytes, item.size)
        XCTAssertEqual(record.category, .largeFiles)
        XCTAssertEqual(historyStore.load().first?.trashedBytes, item.size)
    }

    func testMixedRetryRecordsFreedAndTrashedBytesSeparately() async throws {
        let junk = try makeFile("Library/Caches/stale.tmp", size: 10_000)
        let video = try makeFile("Downloads/holiday.mov", size: 2_000_000)
        let junkItem = CleanableItem(
            name: junk.lastPathComponent,
            path: junk.path,
            size: 10_000,
            category: .systemJunk,
            isSelected: true,
            lastModified: Date()
        )
        let videoItem = trashedItem(
            named: video.lastPathComponent,
            path: video.path,
            size: 2_000_000,
            category: .largeFiles
        )
        let state = makeState()

        await state.retryAfterFullDiskAccess(
            items: [junkItem, videoItem],
            context: .cleanup(failedCount: 2)
        )

        let record = try XCTUnwrap(state.cleanupHistory.first)
        XCTAssertEqual(record.freedBytes, junkItem.size, "Only the unlinked cache is freed space")
        XCTAssertEqual(record.trashedBytes, videoItem.size, "The video's bytes stay in the Trash")
        XCTAssertNil(record.category, "A mixed batch gets no single category")
        XCTAssertFalse(fileManager.fileExists(atPath: junk.path))
        XCTAssertTrue(fileManager.fileExists(atPath: trash.appendingPathComponent("holiday.mov").path))
    }

    func testAFailedTrashMoveWritesNoHistory() async throws {
        let file = try makeFile("Downloads/locked.mov", size: 1_000_000)
        let item = trashedItem(named: file.lastPathComponent, path: file.path, size: 1_000_000, category: .largeFiles)
        let state = makeState(trashOperation: { _ in
            throw NSError(
                domain: "CleanupHistoryTrashTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The Trash is full"]
            )
        })
        state.categoryResults[.largeFiles] = CategoryResult(
            category: .largeFiles,
            items: [item],
            totalSize: item.size
        )

        state.cleanCategory(.largeFiles)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertTrue(state.cleanupHistory.isEmpty, "Nothing moved and nothing was freed: no history row")
        XCTAssertTrue(fileManager.fileExists(atPath: file.path), "A refused Trash move leaves the file alone")
    }

    // MARK: - Fixtures

    private func makeState(
        trashOperation: ((URL) throws -> String?)? = nil
    ) -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false }),
            cleaningEngine: CleaningEngine(
                homeDirectory: home,
                isAppRunning: { _ in false },
                trashOperation: trashOperation ?? { [trash, fileManager] url in
                    let destination = try XCTUnwrap(trash).appendingPathComponent(url.lastPathComponent)
                    try fileManager.moveItem(at: url, to: destination)
                    return destination.path
                }
            ),
            historyStore: historyStore
        )
    }

    private func trashedItem(
        named name: String,
        path: String,
        size: Int64,
        category: CleaningCategory
    ) -> CleanableItem {
        CleanableItem(
            name: name,
            path: path,
            size: size,
            category: category,
            isSelected: true,
            lastModified: Date(),
            movesToTrash: true
        )
    }

    @discardableResult
    private func makeFile(_ relative: String, size: Int) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: size).write(to: url)
        return url
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