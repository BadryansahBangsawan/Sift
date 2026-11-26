import XCTest
@testable import Sift

/// A symlink planted after the scan must not redirect a delete. The cleaner
/// re-checks the path it is about to touch; this test swaps the parent folder
/// for a symlink to another cache folder once the scan item exists.
///
/// Note: this exercises the symlink refusal that runs before the path is
/// resolved again right before the delete. The late re-resolve narrows a
/// mid-call race and has no deterministic filesystem trigger, so it is not
/// isolated here.
final class CleaningEngineSwapTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        home = fileManager.temporaryDirectory
            .appendingPathComponent("SiftSwap-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home { try? fileManager.removeItem(at: home) }
        try super.tearDownWithError()
    }

    func testParentSwappedForSymlinkAfterTheScanIsRefused() async throws {
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let watched = caches.appendingPathComponent("watched", isDirectory: true)
        let precious = caches.appendingPathComponent("precious", isDirectory: true)
        try fileManager.createDirectory(at: watched, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: precious, withIntermediateDirectories: true)
        let victim = watched.appendingPathComponent("victim.bin")
        let sentinel = precious.appendingPathComponent("victim.bin")
        try Data(repeating: 0x41, count: 8_192).write(to: victim)
        try Data(repeating: 0x42, count: 8_192).write(to: sentinel)

        // The item came from a scan; then the parent is swapped for a link.
        let item = CleanableItem(
            name: "victim.bin",
            path: victim.path,
            size: 8_192,
            category: .userCache,
            isSelected: true,
            lastModified: Date()
        )
        let movedAside = caches.appendingPathComponent("watched-real", isDirectory: true)
        try fileManager.moveItem(at: watched, to: movedAside)
        try fileManager.createSymbolicLink(at: watched, withDestinationURL: precious)

        let result = await CleaningEngine(homeDirectory: home, isAppRunning: { _ in false })
            .cleanItems([item]) { _ in }

        XCTAssertTrue(
            fileManager.fileExists(atPath: sentinel.path),
            "a symlink swapped in after the scan must not redirect the delete"
        )
        XCTAssertFalse(result.cleanedPaths.contains(item.path), "the swapped path is not cleaned")
        XCTAssertTrue(result.freedSpace == 0)
    }
}