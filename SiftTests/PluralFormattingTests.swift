import XCTest

/// A plural entry that also carries a size gets two arguments, and Foundation
/// binds them by position. When a form dropped the number, the size landed in
/// the number's slot: the label read "(null)" and the process crashed. These
/// tests format the shape the app actually calls, in the languages with the
/// most forms.
final class PluralFormattingTests: XCTestCase {
    private let size = "1,12 GB"
    private let counts = [0, 1, 2, 3, 5, 11, 12, 21, 100]

    func testASizeArgumentNeverFallsIntoTheNumbersSlot() throws {
        for language in ["en", "de", "ru", "uk", "pl", "ar", "ja", "zh-Hans"] {
            let bundle = try localizationBundle(for: language)
            let locale = Locale(identifier: language)
            for count in counts {
                let text = String(localized: "\(count) items, \(size)", bundle: bundle, locale: locale)
                XCTAssertFalse(text.contains("(null)"), "\(language) \(count): \(text)")
                XCTAssertTrue(
                    text.rangeOfCharacter(from: .decimalDigits) != nil,
                    "\(language) \(count) lost its number: \(text)")
                XCTAssertTrue(text.contains("1,12 GB") || text.contains("1.12 GB"),
                              "\(language) \(count) lost its size: \(text)")
            }
        }
    }

    /// The two-variable label binds both counts and the size.
    func testTheSelectedOfTotalLabelKeepsBothCounts() throws {
        for language in ["en", "de", "ru", "pl", "ar"] {
            let bundle = try localizationBundle(for: language)
            let locale = Locale(identifier: language)
            for count in [1, 2, 5] {
                let text = String(localized: "\(count) of \(5) items, \(size)", bundle: bundle, locale: locale)
                XCTAssertFalse(text.contains("(null)"), "\(language) \(count): \(text)")
            }
        }
    }

    private func localizationBundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "Expected \(language).lproj in the built app bundle")
        return try XCTUnwrap(Bundle(path: path))
    }
}
