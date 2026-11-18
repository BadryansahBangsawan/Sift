import XCTest

/// Counts were rendered as "%@ items" from a plain string table, so every
/// language said "1 items". The tables now carry plural rules per language.
final class PluralizationTests: XCTestCase {
    func testEnglishCountsAgreeWithTheirNumber() throws {
        let en = try localizationBundle(for: "en")
        let english = Locale(identifier: "en")

        XCTAssertEqual(String(localized: "\(1) items", bundle: en, locale: english), "1 item")
        XCTAssertEqual(String(localized: "\(2) items", bundle: en, locale: english), "2 items")
        XCTAssertEqual(String(localized: "\(5) items", bundle: en, locale: english), "5 items")
        XCTAssertEqual(String(localized: "\(0) items", bundle: en, locale: english), "0 items")
    }

    func testRussianCountsUseOneFewAndMany() throws {
        let ru = try localizationBundle(for: "ru")
        let russian = Locale(identifier: "ru")

        XCTAssertEqual(String(localized: "\(1) items", bundle: ru, locale: russian), "1 объект")
        XCTAssertEqual(String(localized: "\(2) items", bundle: ru, locale: russian), "2 объекта")
        XCTAssertEqual(String(localized: "\(5) items", bundle: ru, locale: russian), "5 объектов")
        XCTAssertEqual(String(localized: "\(21) items", bundle: ru, locale: russian), "21 объект")
        XCTAssertEqual(String(localized: "\(11) items", bundle: ru, locale: russian), "11 объектов")
    }

    // MARK: - Helpers

    private func localizationBundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "Expected \(language).lproj in the built app bundle"
        )
        return try XCTUnwrap(Bundle(path: path))
    }
}
