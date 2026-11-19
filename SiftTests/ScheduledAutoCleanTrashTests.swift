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
