import XCTest
@testable import Sift

final class CleanupHistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanupHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testRecordsWrittenBeforeTitleAndCategoryStillLoad() throws {
        let file = directory.appendingPathComponent("history.json")
        let legacy = """
        [
          {
            "date" : "2026-11-02T10:00:00Z",
            "freedBytes" : 2048,
            "source" : "scheduled"
          },
          {
            "date" : "2026-11-05T10:00:00Z",
            "freedBytes" : 4096,
            "source" : "manual"
          }
        ]
        """
        try Data(legacy.utf8).write(to: file)

        let records = CleanupHistoryStore(fileURL: file).load()

        XCTAssertEqual(records.map(\.freedBytes), [4096, 2048])
        XCTAssertEqual(records.map(\.source), [.manual, .scheduled])
        XCTAssertEqual(records.map(\.title), [nil, nil])
        XCTAssertEqual(records.map(\.category), [nil, nil])
    }

    func testTitleAndCategoryRoundTripThroughDisk() {
        let file = directory.appendingPathComponent("history.json")
        CleanupHistoryStore(fileURL: file).record(
            freedBytes: 1_000,
            source: .manual,
            title: "User Cache",
            category: .userCache
        )

        let loaded = CleanupHistoryStore(fileURL: file).load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "User Cache")
        XCTAssertEqual(loaded.first?.category, .userCache)
    }

    func testUnknownCategoryDoesNotDiscardTheHistory() throws {
        let file = directory.appendingPathComponent("history.json")
        let json = """
        [
          {
            "category" : "Withdrawn Category",
            "date" : "2026-11-05T10:00:00Z",
            "freedBytes" : 4096,
            "source" : "manual",
            "title" : "Old"
          }
        ]
        """
        try Data(json.utf8).write(to: file)

        let records = CleanupHistoryStore(fileURL: file).load()

        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records.first?.category)
        XCTAssertEqual(records.first?.title, "Old")
    }

    func testThisMonthKeepsOnlyRecordsInTheCurrentCalendarMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)))
        let records = [
            record(year: 2026, month: 12, day: 1, bytes: 1, calendar: calendar),
            record(year: 2026, month: 11, day: 30, bytes: 10, calendar: calendar),
            record(year: 2026, month: 11, day: 1, bytes: 100, calendar: calendar),
            record(year: 2026, month: 10, day: 31, bytes: 1_000, calendar: calendar),
            record(year: 2025, month: 11, day: 18, bytes: 10_000, calendar: calendar),
        ]

        let thisMonth = CleanupRecord.thisMonth(records, now: now, calendar: calendar)

        XCTAssertEqual(thisMonth.map(\.freedBytes), [10, 100])
        XCTAssertEqual(CleanupRecord.totalFreed(thisMonth), 110)
    }

    func testTotalFreedSaturatesInsteadOfOverflowing() {
        let records = [
            CleanupRecord(date: Date(timeIntervalSince1970: 1), freedBytes: .max, source: .manual),
            CleanupRecord(date: Date(timeIntervalSince1970: 2), freedBytes: 5, source: .manual),
        ]
        XCTAssertEqual(CleanupRecord.totalFreed(records), .max)
    }

    private func record(year: Int, month: Int, day: Int, bytes: Int64, calendar: Calendar) -> CleanupRecord {
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 1))!
        return CleanupRecord(date: date, freedBytes: bytes, source: .manual)
    }
}
