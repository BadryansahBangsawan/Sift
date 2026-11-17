import XCTest
@testable import PureMac

final class ScheduleConfigTests: XCTestCase {
    /// Shape written by builds before weekday/hour existed.
    private let oldShapeJSON = """
    {"isEnabled":true,"interval":"Weekly","autoClean":true,"autoPurge":false,\
    "categoriesToScan":["System Junk","User Cache"],"lastRunDate":785000000,\
    "notifyOnCompletion":false,"minimumCleanSize":52428800}
    """

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    // MARK: - Decoding old configs

    func testOldConfigDecodesWithDefaultWeekdayAndHour() throws {
        let config = try JSONDecoder().decode(ScheduleConfig.self, from: Data(oldShapeJSON.utf8))

        XCTAssertEqual(config.weekday, 1)
        XCTAssertEqual(config.hour, 10)
        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.interval, .weekly)
        XCTAssertTrue(config.autoClean)
        XCTAssertEqual(config.categoriesToScan, [.systemJunk, .userCache])
        XCTAssertEqual(config.lastRunDate, Date(timeIntervalSinceReferenceDate: 785_000_000))
        XCTAssertFalse(config.notifyOnCompletion)
        XCTAssertEqual(config.minimumCleanSize, 52_428_800)
    }

    func testOldConfigWithARemovedCategoryKeepsItsScheduleAndResetsCategories() throws {
        let json = oldShapeJSON.replacingOccurrences(of: "\"User Cache\"", with: "\"Trash Bins\"")

        let config = try JSONDecoder().decode(ScheduleConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.interval, .weekly)
        XCTAssertEqual(config.categoriesToScan, CleaningCategory.scannable)
    }

    func testOutOfRangeWeekdayAndHourFallBackToDefaults() throws {
        let json = oldShapeJSON.replacingOccurrences(of: "}", with: ",\"weekday\":9,\"hour\":24}")

        let config = try JSONDecoder().decode(ScheduleConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.weekday, 1)
        XCTAssertEqual(config.hour, 10)
    }

    func testWeekdayAndHourSurviveARoundTrip() throws {
        var config = ScheduleConfig()
        config.weekday = 4
        config.hour = 21

        let decoded = try JSONDecoder().decode(ScheduleConfig.self, from: JSONEncoder().encode(config))

        XCTAssertEqual(decoded.weekday, 4)
        XCTAssertEqual(decoded.hour, 21)
    }

    // MARK: - Restoring from storage

    func testRestoredConfigResetsWithdrawnCategories() throws {
        let json = oldShapeJSON.replacingOccurrences(of: "\"User Cache\"", with: "\"Universal Binaries\"")

        let config = SchedulerService.restoredConfig(from: Data(json.utf8), now: date("2026-11-18T12:00:00Z"))

        XCTAssertTrue(config.isEnabled)
        XCTAssertEqual(config.categoriesToScan, CleaningCategory.scannable)
    }

    func testRestoredConfigDropsAPastNextRunDate() throws {
        let now = date("2026-11-18T12:00:00Z")
        var saved = ScheduleConfig()
        saved.isEnabled = true
        saved.lastRunDate = now.addingTimeInterval(-86_400)
        saved.nextRunDate = now.addingTimeInterval(-10)

        let config = SchedulerService.restoredConfig(from: try JSONEncoder().encode(saved), now: now)

        XCTAssertTrue(config.isEnabled)
        XCTAssertNil(config.nextRunDate)
        XCTAssertNil(config.lastRunDate)
    }

    func testRestoredConfigFallsBackToDefaultsForMissingOrUnreadableData() {
        XCTAssertFalse(SchedulerService.restoredConfig(from: nil, now: Date()).isEnabled)
        XCTAssertFalse(SchedulerService.restoredConfig(from: Data("not json".utf8), now: Date()).isEnabled)
    }

    // MARK: - Next run date

    func testWeeklyRunsOnTheNextMatchingWeekdayAndHour() {
        var config = ScheduleConfig()
        config.interval = .weekly
        config.weekday = 1
        config.hour = 10

        // 2026-11-18 is a Wednesday.
        let next = SchedulerService.nextRunDate(for: config, now: date("2026-11-18T12:00:00Z"), calendar: utc)

        XCTAssertEqual(next, date("2026-11-22T10:00:00Z"))
    }

    func testWeeklyRunsLaterTheSameDayWhenTheHourIsStillAhead() {
        var config = ScheduleConfig()
        config.interval = .weekly
        config.weekday = 4
        config.hour = 13

        let next = SchedulerService.nextRunDate(for: config, now: date("2026-11-18T12:00:00Z"), calendar: utc)

        XCTAssertEqual(next, date("2026-11-18T13:00:00Z"))
    }

    func testWeeklyAtTheExactRunTimeSchedulesTheFollowingWeek() {
        var config = ScheduleConfig()
        config.interval = .weekly
        config.weekday = 1
        config.hour = 10

        let next = SchedulerService.nextRunDate(for: config, now: date("2026-11-22T10:00:00Z"), calendar: utc)

        XCTAssertEqual(next, date("2026-11-29T10:00:00Z"))
    }

    func testNonWeeklyIntervalsStillCountFromTheLastRun() {
        var config = ScheduleConfig()
        config.interval = .daily
        let now = date("2026-11-18T12:00:00Z")

        XCTAssertEqual(SchedulerService.nextRunDate(for: config, now: now, calendar: utc),
                       date("2026-11-19T12:00:00Z"))

        config.lastRunDate = date("2026-11-18T08:00:00Z")
        XCTAssertEqual(SchedulerService.nextRunDate(for: config, now: now, calendar: utc),
                       date("2026-11-19T08:00:00Z"))
    }

    // MARK: - Display

    func testWeekdaySymbolComesFromTheCalendarLocale() {
        var config = ScheduleConfig()
        XCTAssertEqual(config.weekdaySymbol(calendar: utc), "Sunday")

        config.weekday = 7
        XCTAssertEqual(config.weekdaySymbol(calendar: utc), "Saturday")

        var french = utc
        french.locale = Locale(identifier: "fr_FR")
        config.weekday = 1
        XCTAssertEqual(config.weekdaySymbol(calendar: french), "dimanche")
    }
}
