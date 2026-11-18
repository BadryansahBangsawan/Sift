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

    /// The counts outside the original twelve: folder rows, process rows,
    /// schedule runs, battery cycles, the selection bar and the details labels.
    func testRemainingCountsAgreeWithTheirNumber() throws {
        let en = try localizationBundle(for: "en")
        let english = Locale(identifier: "en")
        let size = "2 MB"

        XCTAssertEqual(String(localized: "\(1) folders", bundle: en, locale: english), "1 folder")
        XCTAssertEqual(String(localized: "\(3) folders", bundle: en, locale: english), "3 folders")
        XCTAssertEqual(String(localized: "\(1) processes", bundle: en, locale: english), "1 process")
        XCTAssertEqual(String(localized: "\(1) runs", bundle: en, locale: english), "1 run")
        XCTAssertEqual(String(localized: "\(1) cycles", bundle: en, locale: english), "1 cycle")
        XCTAssertEqual(String(localized: "\(1) checks", bundle: en, locale: english), "1 check")
        XCTAssertEqual(String(localized: "\(1) areas", bundle: en, locale: english), "1 area")
        XCTAssertEqual(String(localized: "\(1) items found", bundle: en, locale: english), "1 item found")
        XCTAssertEqual(String(localized: "\(1) exact copies · \(size) each", bundle: en, locale: english),
                       "1 exact copy · 2 MB each")
        XCTAssertEqual(String(localized: "Clean \(1) items", bundle: en, locale: english), "Clean 1 item")
        XCTAssertEqual(String(localized: "Permanently remove \(1) items", bundle: en, locale: english),
                       "Permanently remove 1 item")
        XCTAssertEqual(String(localized: "Every \(1) seconds", bundle: en, locale: english), "Every 1 second")
        XCTAssertEqual(String(localized: "of \(1) cores", bundle: en, locale: english), "of 1 core")
        XCTAssertEqual(String(localized: "\(1) backup locations could not be included", bundle: en, locale: english),
                       "1 backup location could not be included")
        XCTAssertEqual(String(localized: "\(1) backups moved to the Trash", bundle: en, locale: english),
                       "1 backup moved to the Trash")
        XCTAssertEqual(
            String(localized: "\(1) folders totaling \(size) will be moved to Trash. Sift checks each folder again first. Reinstall dependencies or rebuild to get them back.",
                   bundle: en, locale: english),
            "1 folder totaling 2 MB will be moved to Trash. Sift checks each folder again first. Reinstall dependencies or rebuild to get it back."
        )
        XCTAssertEqual(
            String(localized: "\(1) folders totaling \(size) are in the Trash. Empty the Trash to free the space.",
                   bundle: en, locale: english),
            "1 folder totaling 2 MB is in the Trash. Empty the Trash to free the space."
        )
    }

    /// The label whose noun follows the total, not the selected count.
    func testOfTotalPluralisesTheTotal() throws {
        let en = try localizationBundle(for: "en")
        let english = Locale(identifier: "en")
        XCTAssertEqual(String(localized: "\(3) of \(1) items, \("2 MB")", bundle: en, locale: english),
                       "3 of 1 item, 2 MB")
        XCTAssertEqual(String(localized: "\(1) of \(3) items, \("2 MB")", bundle: en, locale: english),
                       "1 of 3 items, 2 MB")

        // French attaches the noun to the selected count instead.
        let fr = try localizationBundle(for: "fr")
        let french = Locale(identifier: "fr")
        XCTAssertEqual(String(localized: "\(1) of \(3) items, \("2 MB")", bundle: fr, locale: french),
                       "1 élément sur 3, 2 MB")
        XCTAssertEqual(String(localized: "\(3) of \(1) items, \("2 MB")", bundle: fr, locale: french),
                       "3 éléments sur 1, 2 MB")
    }

    /// The Slavic and Arabic forms for the new keys, at their boundaries.
    func testRemainingCountsFollowEachLanguage() throws {
        let ru = try localizationBundle(for: "ru")
        let russian = Locale(identifier: "ru")
        XCTAssertEqual(String(localized: "\(1) folders", bundle: ru, locale: russian), "Папка: 1")
        XCTAssertEqual(String(localized: "\(2) folders", bundle: ru, locale: russian), "Папки: 2")
        XCTAssertEqual(String(localized: "\(5) folders", bundle: ru, locale: russian), "Папок: 5")
        XCTAssertEqual(String(localized: "\(21) folders", bundle: ru, locale: russian), "Папка: 21")
        XCTAssertEqual(String(localized: "\(11) folders", bundle: ru, locale: russian), "Папок: 11")

        let pl = try localizationBundle(for: "pl")
        let polish = Locale(identifier: "pl")
        XCTAssertEqual(String(localized: "\(1) processes", bundle: pl, locale: polish), "1 proces")
        XCTAssertEqual(String(localized: "\(3) processes", bundle: pl, locale: polish), "3 procesy")
        XCTAssertEqual(String(localized: "\(12) processes", bundle: pl, locale: polish), "12 procesów")

        let ar = try localizationBundle(for: "ar")
        let arabic = Locale(identifier: "ar")
        XCTAssertEqual(String(localized: "\(1) folders", bundle: ar, locale: arabic), "مجلد واحد")
        XCTAssertEqual(String(localized: "\(2) folders", bundle: ar, locale: arabic), "مجلدان")
        XCTAssertEqual(String(localized: "\(3) folders", bundle: ar, locale: arabic), "3 مجلدات")
        XCTAssertEqual(String(localized: "\(11) folders", bundle: ar, locale: arabic), "11 مجلدًا")
        XCTAssertEqual(String(localized: "\(100) folders", bundle: ar, locale: arabic), "100 مجلد")
    }

    /// The composed labels keep their size suffix and pluralise the noun.
    func testComposedLabelsKeepTheSizeSuffix() throws {
        let ru = try localizationBundle(for: "ru")
        let locale = Locale(identifier: "ru")

        XCTAssertEqual(String(localized: "\(2) items · \("1.5 MB")", bundle: ru, locale: locale), "2 объекта · 1.5 MB")
        XCTAssertEqual(String(localized: "Remove \(5) files", bundle: ru, locale: locale), "Удалить 5 файлов")
    }
}
