import XCTest

@testable import Sift

/// Every screen is named the way the rail names it, so a page and the button
/// that opened it never disagree. These are the keys the headings, the
/// onboarding rows and the Leftovers copy use.
final class ScreenNamesTests: XCTestCase {
    private let keys = [
        "Overview", "Uninstaller", "Leftovers",
        "Space explorer", "Duplicates", "Similar photos",
        "Apple features", "App updates",
    ]

    func testEveryLanguageNamesEveryScreen() throws {
        for language in AppLanguage.allCases.map(\.rawValue) where language != "system" {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertFalse(value.isEmpty, "\(language) has no “\(key)”")
                if language != "en" {
                    XCTAssertNotEqual(value, key,
                                      "\(language) still shows the English “\(key)”")
                }
            }
        }
    }
}
