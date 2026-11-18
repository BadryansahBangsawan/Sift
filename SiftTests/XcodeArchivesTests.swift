import XCTest
@testable import Sift

/// Xcode Archives hold the app's shipped builds and the dSYMs needed to
/// symbolicate crash reports, so they are the user's work: never pre-selected,
/// and moved to the Trash rather than unlinked.
final class XcodeArchivesTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!

    override func setUpWithError() throws {
        home = fileManager.temporaryDirectory
            .appendingPathComponent("PureMac-XcodeArchives-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try createFile("Library/Developer/Xcode/Archives/2024-05-02/App 1.4.xcarchive/Info.plist")
        try createFile("Library/Developer/Xcode/DerivedData/App-hash/Build/objects.o")
        try createFile("Library/Developer/Xcode/iOS DeviceSupport/17.5/System.img")
    }

    override func tearDownWithError() throws {
        if let home, fileManager.fileExists(atPath: home.path) {
            try fileManager.removeItem(at: home)
        }
    }

    func testArchivesAreOptInAndMovedToTheTrash() async throws {
        let scan = await makeScanner().scanCategory(.xcodeJunk)
        let items = Dictionary(uniqueKeysWithValues: scan.items.map { ($0.path, $0) })

        let archives = try XCTUnwrap(items[path("Library/Developer/Xcode/Archives")])
        XCTAssertFalse(
            archives.isSelected,
            "Archives are shipped builds and dSYMs that cannot be regenerated: never pre-select user work"
        )
        XCTAssertNotNil(archives.note, "The row must say what is lost before the user opts in")
        XCTAssertTrue(archives.movesToTrash, "Archives must be recoverable, not unlinked")

        XCTAssertEqual(items[path("Library/Developer/Xcode/DerivedData")]?.isSelected, true)
        XCTAssertEqual(items[path("Library/Developer/Xcode/iOS DeviceSupport")]?.isSelected, true)
    }

    func testCleaningArchivesMovesThemToTheTrash() async throws {
        let scan = await makeScanner().scanCategory(.xcodeJunk)
        let archives = try XCTUnwrap(scan.items.first { $0.path == path("Library/Developer/Xcode/Archives") })
        var selected = archives
        selected.isSelected = true

        let result = await makeCleaner().cleanItems([selected]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 1, "\(result.errors)")
        XCTAssertFalse(
            fileManager.fileExists(atPath: archives.path),
            "The archive folder leaves ~/Library/Developer/Xcode"
        )
        XCTAssertEqual(result.trashedPaths.count, 1, "Archives go to the Trash")
        XCTAssertEqual(result.freedSpace, 0, "A Trash move reclaims nothing until the Trash is emptied")
        for trashed in result.trashedPaths {
            try? fileManager.removeItem(atPath: trashed)
        }
    }

    func testScheduledCleanSkipsArchivesUnlessTheUserOptedIn() async throws {
        let state = AppState(performStartupTasks: false)
        let scan = await makeScanner().scanCategory(.xcodeJunk)
        state.categoryResults[.xcodeJunk] = scan

        let selected = state.categoryResults[.xcodeJunk]?.items.filter { state.isItemSelected($0) } ?? []

        XCTAssertFalse(
            selected.contains { $0.path == path("Library/Developer/Xcode/Archives") },
            "An unattended clean must never include Archives unless the user selected them"
        )
        XCTAssertTrue(selected.contains { $0.path == path("Library/Developer/Xcode/DerivedData") })
    }

    func testOtherXcodeRowsStillUnlinkAndCountAsFreed() async throws {
        let scan = await makeScanner().scanCategory(.xcodeJunk)
        let deviceSupport = try XCTUnwrap(
            scan.items.first { $0.path == path("Library/Developer/Xcode/iOS DeviceSupport") }
        )

        let result = await makeCleaner().cleanItems([deviceSupport]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 1, "\(result.errors)")
        XCTAssertTrue(result.trashedPaths.isEmpty, "Regenerable caches are unlinked, not recycled")
        XCTAssertEqual(result.freedSpace, deviceSupport.size)
        XCTAssertFalse(fileManager.fileExists(atPath: deviceSupport.path))
    }

    // MARK: - Fixtures

    private func makeScanner() -> ScanEngine {
        ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false })
    }

    private func makeCleaner() -> CleaningEngine {
        CleaningEngine(homeDirectory: home, isAppRunning: { _ in false })
    }

    private func path(_ relative: String) -> String {
        home.appendingPathComponent(relative).path
    }

    private func createFile(_ relative: String, size: Int = 4096) throws {
        let url = home.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: size).write(to: url)
    }
}
