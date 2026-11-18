import XCTest

@testable import Sift

/// The rail's schedule card said "Scheduled cleanup" next to a switch that, by
/// default, only scans — Settings calls it "Enable scheduled scanning" and
/// auto-clean is off. The card now names what the schedule will actually do.
final class ScheduledCopyTests: XCTestCase {
    func testTheCardNamesWhatTheScheduleDoes() {
        var scanning = ScheduleConfig()
        scanning.isEnabled = true
        XCTAssertEqual(scanning.railTitleKey, "Scheduled scan",
                       "A schedule that only scans must not promise a cleanup")

        var cleaning = scanning
        cleaning.autoClean = true
        XCTAssertEqual(cleaning.railTitleKey, "Scheduled cleanup")
    }

    func testEveryLanguageNamesTheScan() throws {
        var checked = 0
        for language in AppLanguage.allCases.map(\.rawValue) where language != "system" {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let value = bundle.localizedString(forKey: "Scheduled scan", value: nil, table: nil)
            XCTAssertFalse(value.isEmpty || value == "Scheduled scan" && language != "en",
                           "\(language) has no translation of “Scheduled scan”")
            checked += 1
        }
        XCTAssertEqual(checked, 13)
    }
}
