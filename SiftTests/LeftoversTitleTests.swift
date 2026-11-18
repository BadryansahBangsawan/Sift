import XCTest

@testable import Sift

/// The Leftovers page called itself "Orphaned Files" above the heading, and it
/// counted before it had looked: a fresh page said "Orphaned Files (0)". The
/// eyebrow now uses the screen's name and shows no number until a scan
/// finished.
final class LeftoversTitleTests: XCTestCase {
    func testBeforeAScanThereIsNoNumber() {
        let title = LeftoversTitle.text(count: 0, scanned: false)
        XCTAssertEqual(title, "Leftovers")
        XCTAssertFalse(title.contains("("), "A count appeared before the scan: \(title)")
        XCTAssertFalse(title.contains("0"), "A count appeared before the scan: \(title)")
    }

    func testAfterAScanTheCountIsShown() {
        XCTAssertEqual(LeftoversTitle.text(count: 0, scanned: true), "Leftovers (0)")
        XCTAssertEqual(LeftoversTitle.text(count: 1, scanned: true), "Leftovers (1)")
        XCTAssertEqual(LeftoversTitle.text(count: 128, scanned: true), "Leftovers (128)")
    }

    /// The name is the rail's, in every language, and it is never the old
    /// "Orphaned Files".
    func testEveryLanguageUsesTheScreensName() throws {
        var checked = 0
        for language in AppLanguage.allCases.map(\.rawValue) where language != "system" {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            let base = bundle.localizedString(forKey: "Leftovers", value: nil, table: nil)
            let counted = bundle.localizedString(forKey: "Leftovers (%lld)", value: nil, table: nil)
            XCTAssertFalse(base.isEmpty, "\(language) has no Leftovers name")
            XCTAssertTrue(counted.contains("%lld"), "\(language) drops the count: \(counted)")
            XCTAssertTrue(counted.hasPrefix(base),
                          "\(language) counts “\(counted)” but names the screen “\(base)”")
            XCTAssertEqual(bundle.localizedString(forKey: "Orphaned Files (%lld)", value: nil, table: nil),
                           "Orphaned Files (%lld)", "\(language) still ships the old eyebrow")
            checked += 1
        }
        XCTAssertEqual(checked, 13)
    }
}
