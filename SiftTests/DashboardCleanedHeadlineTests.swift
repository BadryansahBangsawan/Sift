import XCTest
@testable import Sift

/// After a clean where every row moved to the Trash, freed space is zero but
/// the dashboard must still say where those bytes went.
@MainActor
final class DashboardCleanedHeadlineTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!
    private var trash: URL!
    private var historyFile: URL!
    private var savedExclusions: [String]?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedExclusions = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([], forKey: CleanupExclusions.defaultsKey)
        home = fileManager.temporaryDirectory
            .appendingPathComponent("DashboardHeadline-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        trash = fileManager.temporaryDirectory
            .appendingPathComponent("DashboardHeadlineTrash-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: trash, withIntermediateDirectories: true)
        historyFile = fileManager.temporaryDirectory
            .appendingPathComponent("DashboardHeadlineHistory-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        if let home { try? fileManager.removeItem(at: home) }
        if let trash { try? fileManager.removeItem(at: trash) }
        if let historyFile { try? fileManager.removeItem(at: historyFile) }
        if let savedExclusions {
            UserDefaults.standard.set(savedExclusions, forKey: CleanupExclusions.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
        }
        try super.tearDownWithError()
    }

    func testTrashOnlyCleanupHeadlineSaysWhereTheBytesWent() async throws {
        let item = try makeJunkItem()
        let state = makeState()
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [item],
            totalSize: item.size
        )

        state.cleanAll(scheduled: true)
        try await waitUntil(timeout: 5) { !state.scanState.isActive }

        XCTAssertEqual(state.totalFreedSpace, 0, "Bytes in the Trash are not freed")
        XCTAssertTrue(
            state.lastCleanupHeadline.contains("Moved to Trash"),
            "Headline claimed freed space: \(state.lastCleanupHeadline)"
        )
    }

    // MARK: - Helpers

    private func makeJunkItem() throws -> CleanableItem {
        let cache = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent("junk.bin")
        try Data(repeating: 1, count: 8_192).write(to: file)
        return CleanableItem(
            name: file.lastPathComponent,
            path: file.path,
            size: 8_192,
            category: .systemJunk,
            isSelected: true,
            lastModified: nil
        )
    }

    private func makeState() -> AppState {
        AppState(
            performStartupTasks: false,
            cleaningEngine: CleaningEngine(
                homeDirectory: home,
                isAppRunning: { _ in false },
                trashOperation: { [trash, fileManager] url in
                    let destination = trash!.appendingPathComponent(url.lastPathComponent)
                    try fileManager.moveItem(at: url, to: destination)
                    return destination.path
                }
            ),
            historyStore: CleanupHistoryStore(fileURL: historyFile)
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