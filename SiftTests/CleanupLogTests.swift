import XCTest
@testable import Sift

/// The cleanup log is the audit trail for every path Sift removes. It is local,
/// append-only JSONL, and must never make a cleanup fail.
final class CleanupLogTests: XCTestCase {
    private let fileManager = FileManager.default
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("CleanupLogTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? fileManager.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testWritesOneJSONLinePerRecord() throws {
        let file = directory.appendingPathComponent("cleanup.log")
        let log = CleanupLog(
            fileURL: file,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            version: "4.2.0",
            build: "40"
        )

        log.record(
            source: "manual",
            category: "User Cache",
            action: .trashed,
            path: "/Users/me/Library/Caches/com.example.app",
            bytes: 8_192
        )
        log.record(
            source: "scheduled",
            category: "Project Junk",
            action: .skipped,
            path: "/Users/me/Projects/app/node_modules",
            bytes: nil,
            reason: "Git tracks files inside it"
        )

        let lines = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines.count, 2)

        let first = try decode(lines[0])
        XCTAssertEqual(first.time, "2023-11-14T22:13:20Z")
        XCTAssertEqual(first.version, "4.2.0")
        XCTAssertEqual(first.build, "40")
        XCTAssertEqual(first.source, "manual")
        XCTAssertEqual(first.category, "User Cache")
        XCTAssertEqual(first.action, "trashed")
        XCTAssertEqual(first.path, "/Users/me/Library/Caches/com.example.app")
        XCTAssertEqual(first.bytes, 8_192)
        XCTAssertNil(first.reason)

        let second = try decode(lines[1])
        XCTAssertEqual(second.action, "skipped")
        XCTAssertEqual(second.reason, "Git tracks files inside it")
        XCTAssertNil(second.bytes)
    }

    func testAppendsWithoutDroppingEarlierRecords() throws {
        let file = directory.appendingPathComponent("cleanup.log")
        try Data("{\"existing\":true}\n".utf8).write(to: file)
        let log = CleanupLog(fileURL: file, version: "4.2.0", build: "40")

        log.record(source: "retry", category: nil, action: .removed, path: "/tmp/a")

        let lines = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines.first, "{\"existing\":true}")
        XCTAssertEqual(try decode(lines[1]).source, "retry")
    }

    func testRotatesAtTheSizeLimit() throws {
        let file = directory.appendingPathComponent("cleanup.log")
        let log = CleanupLog(fileURL: file, version: "4.2.0", build: "40", maxBytes: 120)

        log.record(source: "manual", category: nil, action: .removed, path: "/tmp/first", bytes: 1)
        let firstLineSize = try fileManager.attributesOfItem(atPath: file.path)[.size] as? Int ?? 0
        // Force the next record over the limit.
        log.record(
            source: "manual",
            category: nil,
            action: .removed,
            path: "/tmp/second-\(String(repeating: "x", count: 200))",
            bytes: 1
        )

        let rotated = file.appendingPathExtension("1")
        XCTAssertTrue(fileManager.fileExists(atPath: rotated.path), "the old file is renamed to .1")
        let archived = try String(contentsOf: rotated, encoding: .utf8)
        XCTAssertTrue(archived.contains("/tmp/first"))
        XCTAssertGreaterThan(firstLineSize, 0)

        let current = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(current.contains("/tmp/second"))
        XCTAssertFalse(current.contains("/tmp/first"))

        // A second rotation replaces the older .1 instead of growing it.
        log.record(
            source: "manual",
            category: nil,
            action: .removed,
            path: "/tmp/third-\(String(repeating: "y", count: 200))",
            bytes: 1
        )
        let archivedAgain = try String(contentsOf: rotated, encoding: .utf8)
        XCTAssertTrue(archivedAgain.contains("/tmp/second"))
        XCTAssertFalse(archivedAgain.contains("/tmp/first"))
    }

    func testUnwritableDestinationNeverThrows() throws {
        let blocker = directory.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let log = CleanupLog(
            fileURL: blocker.appendingPathComponent("cleanup.log"),
            version: "4.2.0",
            build: "40"
        )

        log.record(source: "manual", category: nil, action: .removed, path: "/tmp/a")
        log.record(source: "manual", category: nil, action: .failed, path: "/tmp/b", reason: "denied")

        XCTAssertFalse(
            fileManager.fileExists(atPath: blocker.appendingPathComponent("cleanup.log").path)
        )
    }

    private func decode(_ line: String) throws -> CleanupLog.Record {
        try JSONDecoder().decode(CleanupLog.Record.self, from: Data(line.utf8))
    }
}