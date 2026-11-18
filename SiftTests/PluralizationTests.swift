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

extension PluralizationTests {
    func testPolishCoversFewAndMany() throws {
        let pl = try localizationBundle(for: "pl")
        let locale = Locale(identifier: "pl")

        XCTAssertEqual(String(localized: "\(1) files", bundle: pl, locale: locale), "1 plik")
        XCTAssertEqual(String(localized: "\(3) files", bundle: pl, locale: locale), "3 pliki")
        XCTAssertEqual(String(localized: "\(12) files", bundle: pl, locale: locale), "12 plików")
    }

    func testArabicCoversTheDualForm() throws {
        let ar = try localizationBundle(for: "ar")
        let locale = Locale(identifier: "ar")

        XCTAssertEqual(String(localized: "\(1) photos", bundle: ar, locale: locale), "صورة واحدة")
        XCTAssertEqual(String(localized: "\(2) photos", bundle: ar, locale: locale), "صورتان")
        XCTAssertEqual(String(localized: "\(5) photos", bundle: ar, locale: locale), "5 صور")
    }

    /// Languages without plural inflection still resolve the count.
    func testJapaneseHasOneFormForEveryNumber() throws {
        let ja = try localizationBundle(for: "ja")
        let locale = Locale(identifier: "ja")

        XCTAssertEqual(String(localized: "\(1) items", bundle: ja, locale: locale), "1件の項目")
        XCTAssertEqual(String(localized: "\(45) items", bundle: ja, locale: locale), "45件の項目")
    }

    /// The composed labels keep their size suffix and pluralise the noun.
    func testComposedLabelsKeepTheSizeSuffix() throws {
        let ru = try localizationBundle(for: "ru")
        let locale = Locale(identifier: "ru")

        XCTAssertEqual(String(localized: "\(2) items · \("1.5 MB")", bundle: ru, locale: locale), "2 объекта · 1.5 MB")
        XCTAssertEqual(String(localized: "Remove \(5) files", bundle: ru, locale: locale), "Удалить 5 файлов")
    }
}
