import XCTest
@testable import Sift

/// A scheduled clean runs with nobody watching, so whatever it removes has to
/// stay recoverable: every row it handles goes to the Trash, and a Trash move
/// never counts as freed space (the Trash emptier records those bytes later).
@MainActor
final class ScheduledAutoCleanTrashTests: XCTestCase {
    private let fileManager = FileManager.default
    /// A real home (for the delete allow-lists) with the junk parked in a
    /// temporary Caches folder under it.
    private var fixtureRoot: URL!
    private var fixtureTrash: URL!
    private var historyFile: URL!
    private var historyStore: CleanupHistoryStore!
    private var savedExclusions: [String]?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedExclusions = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([], forKey: CleanupExclusions.defaultsKey)
        fixtureRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/ScheduledAutoCleanTrashTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        fixtureTrash = fileManager.temporaryDirectory
            .appendingPathComponent("ScheduledAutoCleanTrash-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixtureTrash, withIntermediateDirectories: true)
        historyFile = fileManager.temporaryDirectory
            .appendingPathComponent("ScheduledAutoCleanHistory-\(UUID().uuidString).json")
        historyStore = CleanupHistoryStore(fileURL: historyFile)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot { try? fileManager.removeItem(at: fixtureRoot) }
        if let fixtureTrash { try? fileManager.removeItem(at: fixtureTrash) }
        if let historyFile { try? fileManager.removeItem(at: historyFile) }
        if let savedExclusions {
            UserDefaults.standard.set(savedExclusions, forKey: CleanupExclusions.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
        }
        try super.tearDownWithError()
    }

    func testScheduledCleanMovesJunkToTheTrashAndFreesNothing() async throws {
        let file = try makeFile(named: "junk.bin")
        let item = makeItem(for: file)
        let state = makeState()
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [item],
            totalSize: item.size
        )

        state.cleanAll(scheduled: true)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertFalse(fileManager.fileExists(atPath: file.path), "The junk must leave its folder")
        XCTAssertTrue(
            fileManager.fileExists(atPath: fixtureTrash.appendingPathComponent("junk.bin").path),
            "A scheduled clean must keep the junk recoverable in the Trash"
        )
        XCTAssertEqual(state.totalFreedSpace, 0,
                       "Bytes in the Trash are not freed until the Trash is emptied")
        XCTAssertNil(state.cleanError)
    }

    func testManualCleanOfTheSameJunkStillDeletesItPermanently() async throws {
        let file = try makeFile(named: "junk.bin")
        let item = makeItem(for: file)
        let state = makeState()
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [item],
            totalSize: item.size
        )

        state.cleanAll()
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertFalse(fileManager.fileExists(atPath: file.path))
        XCTAssertFalse(
            fileManager.fileExists(atPath: fixtureTrash.appendingPathComponent("junk.bin").path),
            "A manual clean of ordinary junk is still an unlink, not a Trash move"
        )
        XCTAssertEqual(state.totalFreedSpace, item.size)
    }

    // MARK: - Edges

    /// Action rows have no file to move: a scheduled clean must leave them for
    /// the user instead of running them unattended.
    func testScheduledCleanLeavesActionRowsSelected() async throws {
        let file = try makeFile(named: "junk.bin")
        let junk = makeItem(for: file)
        let docker = CleanableItem(
            name: "Docker prune",
            path: "",
            size: 4_096,
            category: .dockerCache,
            isSelected: true,
            lastModified: nil
        )
        let runtime = CleanableItem(
            name: "iOS 18 Simulator",
            path: CleanableItem.simctlRuntimePathPrefix + "A1B2-C3D4",
            size: 8_192,
            category: .xcodeJunk,
            isSelected: true,
            lastModified: nil
        )
        let state = makeState()
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [junk],
            totalSize: junk.size
        )
        state.categoryResults[.dockerCache] = CategoryResult(
            category: .dockerCache,
            items: [docker],
            totalSize: docker.size
        )
        state.categoryResults[.xcodeJunk] = CategoryResult(
            category: .xcodeJunk,
            items: [runtime],
            totalSize: runtime.size
        )

        state.cleanAll(scheduled: true)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertTrue(fileManager.fileExists(atPath: fixtureTrash.appendingPathComponent("junk.bin").path),
                      "Ordinary junk still goes to the Trash")
        XCTAssertEqual(state.categoryResults[.dockerCache]?.items.map(\.id), [docker.id])
        XCTAssertEqual(state.categoryResults[.xcodeJunk]?.items.map(\.id), [runtime.id])
        XCTAssertTrue(state.isItemSelected(docker), "An action row stays selected for the next manual clean")
        XCTAssertTrue(state.isItemSelected(runtime))
        XCTAssertFalse(state.lastCleanupHadFailures)
        XCTAssertNil(state.cleanError, "A row left for a manual clean is not an error")
    }

    /// A root-owned row cannot be moved to the Trash without a password, which
    /// an unattended clean must never ask for. It stays put and stays selected.
    func testScheduledCleanSkipsRowsThatNeedAdministratorPrivileges() async throws {
        let blocked = fixtureRoot.appendingPathComponent("root-owned", isDirectory: true)
        try fileManager.createDirectory(at: blocked, withIntermediateDirectories: true)
        let file = blocked.appendingPathComponent("system.log")
        try Data(repeating: 2, count: 8_192).write(to: file)
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: blocked.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }

        let item = CleanableItem(
            name: "system.log",
            path: file.path,
            size: 8_192,
            category: .systemJunk,
            isSelected: true,
            lastModified: nil
        )
        let state = makeState()
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [item],
            totalSize: item.size
        )

        state.cleanAll(scheduled: true)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertTrue(fileManager.fileExists(atPath: file.path), "A root-owned row is left alone")
        XCTAssertEqual(state.categoryResults[.systemJunk]?.items.map(\.id), [item.id])
        XCTAssertTrue(state.isItemSelected(item), "The row stays selected for the next manual clean")
        XCTAssertFalse(state.lastCleanupHadFailures)
        XCTAssertTrue(state.cleanupHistory.allSatisfy { $0.freedBytes == 0 && $0.trashedBytes == 0 })
    }

    /// A Trash move that fails is a failure: the row must never be unlinked as
    /// a fallback, because that is exactly the unrecoverable delete an
    /// unattended clean exists to avoid.
    func testFailedTrashMoveIsAnErrorAndNeverAnUnlink() async throws {
        let file = try makeFile(named: "junk.bin")
        let item = makeItem(for: file)
        let state = makeState { _ in
            throw NSError(domain: "ScheduledAutoCleanTrashTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The Trash is full"])
        }
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [item],
            totalSize: item.size
        )

        state.cleanAll(scheduled: true)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertTrue(fileManager.fileExists(atPath: file.path), "No unlink fallback")
        XCTAssertNotNil(state.cleanError)
        XCTAssertTrue(state.lastCleanupHadFailures)
        XCTAssertEqual(state.totalFreedSpace, 0)
    }

    func testScheduledHistoryRecordsTrashedBytesAsNotFreed() async throws {
        let file = try makeFile(named: "junk.bin")
        let item = makeItem(for: file)
        let state = makeState()
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [item],
            totalSize: item.size
        )

        state.cleanAll(scheduled: true)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        let record = try XCTUnwrap(state.cleanupHistory.first)
        XCTAssertEqual(record.source, .scheduled)
        XCTAssertEqual(record.freedBytes, 0, "Trashed bytes are not freed space")
        XCTAssertEqual(record.trashedBytes, item.size)
        XCTAssertEqual(record.category, .systemJunk)
        XCTAssertEqual(historyStore.load().first?.trashedBytes, item.size)
    }

    /// History written before `trashedBytes` existed must still decode.
    func testHistoryWithoutTrashedBytesDecodesAsZero() throws {
        let json = """
        [{"date":"2026-11-01T10:00:00Z","freedBytes":4096,"source":"manual","title":"Emptied Trash","category":"Trash"}]
        """
        try Data(json.utf8).write(to: historyFile)

        let record = try XCTUnwrap(historyStore.load().first)
        XCTAssertEqual(record.freedBytes, 4_096)
        XCTAssertEqual(record.trashedBytes, 0)
    }

    // MARK: - Fixtures

    private func makeFile(named name: String, size: Int = 8_192) throws -> URL {
        let file = fixtureRoot.appendingPathComponent(name)
        try Data(repeating: 1, count: size).write(to: file)
        return file
    }

    private func makeItem(for file: URL) -> CleanableItem {
        CleanableItem(
            name: file.lastPathComponent,
            path: file.path,
            size: 8_192,
            category: .systemJunk,
            isSelected: true,
            lastModified: nil
        )
    }

    private func makeState(
        trashOperation: ((URL) throws -> String?)? = nil
    ) -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: ScanEngine(homeDirectory: fixtureRoot),
            cleaningEngine: CleaningEngine(
                homeDirectory: fileManager.homeDirectoryForCurrentUser,
                trashOperation: trashOperation ?? { [fixtureTrash, fileManager] url in
                    let destination = try XCTUnwrap(fixtureTrash).appendingPathComponent(url.lastPathComponent)
                    try fileManager.moveItem(at: url, to: destination)
                    return destination.path
                }
            ),
            historyStore: historyStore
        )
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

/// AI tool caches and logs are not opt-in rows, so a manual clean unlinks them.
/// That is fine with the user watching; an unattended clean has to keep them
/// recoverable like every other row it touches.
final class UnattendedAICleanTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!
    private var trash: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = fileManager.temporaryDirectory
            .appendingPathComponent("ScheduledAIClean-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        trash = fileManager.temporaryDirectory
            .appendingPathComponent("ScheduledAICleanTrash-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? fileManager.removeItem(at: home) }
        if let trash { try? fileManager.removeItem(at: trash) }
        try super.tearDownWithError()
    }

    func testUnattendedCleanMovesAnAICacheToTheTrash() async throws {
        let cache = home.appendingPathComponent(".claude/shell-snapshots", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 8_192).write(to: cache.appendingPathComponent("snapshot.sh"))
        let item = CleanableItem(
            name: "Claude Code Shell Snapshots",
            path: cache.path,
            size: 8_192,
            category: .aiApps,
            isSelected: true,
            lastModified: nil
        )

        let result = await makeEngine().cleanItems([item], unattended: true) { _ in }

        XCTAssertEqual(result.itemsCleaned, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: cache.path))
        XCTAssertTrue(
            fileManager.fileExists(atPath: trash.appendingPathComponent("shell-snapshots").path),
            "An unattended clean must keep an AI cache recoverable"
        )
        XCTAssertEqual(result.trashedSpace, 8_192)
        XCTAssertEqual(result.freedSpace, 0, "Bytes in the Trash are not freed")
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
            }
        )
    }
}
