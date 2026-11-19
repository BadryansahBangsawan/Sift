import XCTest

@testable import Sift

/// The app-updates eyebrow read "Last checked 1 min, 19 secs" and ticked every
/// second: `Text(date, style: .relative)` is a live duration, not "when". It
/// also concatenated three fragments, which breaks word order in Japanese,
/// Chinese and Arabic.
@MainActor
final class UpdatesEyebrowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAFreshCheckReadsAsJustNow() {
        XCTAssertEqual(AppUpdatesView.checkedLabel(now.addingTimeInterval(-5), now: now), "Last checked just now")
    }

    func testAMinuteLaterReadsAsAMinuteAgo() {
        XCTAssertEqual(AppUpdatesView.checkedLabel(now.addingTimeInterval(-90), now: now), "Last checked 1 minute ago")
        XCTAssertEqual(AppUpdatesView.checkedLabel(now.addingTimeInterval(-3_600), now: now), "Last checked 1 hour ago")
    }

    /// A duration reads "1 min, 19 secs" and never says "ago"; the label must
    /// say when, and stay a single sentence.
    func testTheLabelSaysWhen() {
        let text = AppUpdatesView.checkedLabel(now.addingTimeInterval(-79), now: now)
        XCTAssertFalse(text.contains("sec"), "A live duration leaked in: \(text)")
        XCTAssertTrue(text.contains("ago"), "Expected a relative date: \(text)")
    }

    // MARK: - Range

    /// The whole range a check can age through, including the named day
    /// RelativeDateTimeFormatter switches to after 24 hours.
    func testEveryAgeReadsNaturally() {
        XCTAssertEqual(AppUpdatesView.checkedLabel(now.addingTimeInterval(-5), now: now),
                       "Last checked just now")
        XCTAssertEqual(AppUpdatesView.checkedLabel(now.addingTimeInterval(-60), now: now),
                       "Last checked 1 minute ago")
        XCTAssertEqual(AppUpdatesView.checkedLabel(now.addingTimeInterval(-2 * 3_600), now: now),
                       "Last checked 2 hours ago")
        XCTAssertEqual(AppUpdatesView.checkedLabel(now.addingTimeInterval(-26 * 3_600), now: now),
                       "Last checked yesterday")
    }

    /// Russian puts the date after a colon and keeps its own wording; the
    /// sentence is not assembled from English fragments.
    func testRussianCarriesItsOwnWordOrder() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let ru = try XCTUnwrap(Bundle(path: path))
        let template = ru.localizedString(forKey: "Last checked %@", value: nil, table: nil)
        XCTAssertEqual(template, "Последняя проверка: %@")

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru")
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let when = formatter.localizedString(
            for: now.addingTimeInterval(-26 * 3_600), relativeTo: now)
        XCTAssertEqual(String(format: template, when), "Последняя проверка: \(when)")
        XCTAssertTrue(when.contains("вчера"), "Russian said “\(when)”")
    }

    /// Every shipped language carries the sentence with its own word order.
    func testEveryLanguageHasTheSentence() throws {
        var checked = 0
        for language in AppLanguage.allCases.map(\.rawValue) where language != "system" {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let value = bundle.localizedString(forKey: "Last checked %@", value: nil, table: nil)
            XCTAssertFalse(value.isEmpty, "\(language) has no “Last checked %@”")
            XCTAssertTrue(value.contains("%@"), "\(language) drops the date: \(value)")
            checked += 1
        }
        XCTAssertEqual(checked, 13)
    }
}
