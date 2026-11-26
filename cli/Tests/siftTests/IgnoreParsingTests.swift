import Foundation
import XCTest
@testable import sift

/// Hand-edited ignore files must keep working: worth stripping the whitespace a
/// text editor leaves behind, while still refusing genuinely invalid entries.
final class IgnoreParsingTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!
    private var ignoreFile: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = fileManager.temporaryDirectory
            .appendingPathComponent("sift-ignore-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        ignoreFile = root.appendingPathComponent("ignore")
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testTrailingSpacesOnAnEntryStillProtectTheFolder() throws {
        let protected = try makeProtectedFolder(name: "kept folder")
        try Data("\(protected.path)   \n".utf8).write(to: ignoreFile)

        let store = try makeStore()

        XCTAssertEqual(store.roots, [protected.path])
        XCTAssertTrue(
            Safety.isPathIgnored(protected.appendingPathComponent("file.bin").path, ignore: store),
            "a trailing space left by an editor must not disarm the entry"
        )
    }

    func testCRLFFileStillProtectsEveryEntry() throws {
        let first = try makeProtectedFolder(name: "first")
        let second = try makeProtectedFolder(name: "second")
        try Data("\(first.path)\r\n\(second.path)\r\n".utf8).write(to: ignoreFile)

        let store = try makeStore()

        XCTAssertEqual(store.roots.sorted(), [first.path, second.path].sorted())
        XCTAssertTrue(Safety.isPathIgnored(first.appendingPathComponent("a.bin").path, ignore: store))
        XCTAssertTrue(Safety.isPathIgnored(second.appendingPathComponent("b.bin").path, ignore: store))
    }

    func testSurroundingWhitespaceKeepsInternalSpaces() throws {
        let protected = try makeProtectedFolder(name: "kept folder")
        try Data("\t \(protected.path) \t\n".utf8).write(to: ignoreFile)

        let store = try makeStore()

        XCTAssertEqual(store.roots, [protected.path])
    }

    func testBlankLinesAndDuplicatesAreIgnored() throws {
        let protected = try makeProtectedFolder(name: "kept")
        try Data("\n   \n\t\n\(protected.path)\n  \(protected.path)  \n".utf8).write(to: ignoreFile)

        let store = try makeStore()

        XCTAssertEqual(store.roots, [protected.path])
    }

    func testClassicMacLineEndingsStillWork() throws {
        let first = try makeProtectedFolder(name: "first")
        let second = try makeProtectedFolder(name: "second")
        try Data("\(first.path)\r\(second.path)\r".utf8).write(to: ignoreFile)

        let store = try makeStore()

        XCTAssertEqual(store.roots.sorted(), [first.path, second.path].sorted())
    }

    func testInvalidEntriesAreStillRejected() throws {
        let protected = try makeProtectedFolder(name: "kept")
        try Data("relative/path\n/\n\(protected.path)\n".utf8).write(to: ignoreFile)

        let store = try makeStore()

        XCTAssertEqual(store.roots, [protected.path], "a bad line is skipped, not the whole file")
    }

    // MARK: - Fixtures

    private func makeProtectedFolder(name: String) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func makeStore() throws -> IgnoreStore {
        try IgnoreStore(fileURL: ignoreFile, legacyFileURL: nil, currentDirectoryPath: root.path)
    }
}