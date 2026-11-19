import XCTest

/// The plural tables are data, not code: a key added to one language only, a
/// form set that does not match the language, or a form that drops an argument
/// all fail silently at runtime and render the wrong sentence. These checks
/// read the tables the app ships.
final class PluralTablesTests: XCTestCase {
    private let languages = ["ar", "de", "en", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant"]

    /// The categories CLDR selects for each language, so a table cannot be
    /// missing a form the system will ask for.
    private let categories: [String: Set<String>] = [
        "ar": ["zero", "one", "two", "few", "many", "other"],
        "ru": ["one", "few", "many", "other"],
        "uk": ["one", "few", "many", "other"],
        "pl": ["one", "few", "many", "other"],
        "ja": ["other"],
        "zh-Hans": ["other"],
        "zh-Hant": ["other"],
        "de": ["one", "other"],
        "en": ["one", "other"],
        "es": ["one", "other"],
        "fr": ["one", "other"],
        "it": ["one", "other"],
        "pt-BR": ["one", "other"],
    ]

    func testEveryLanguageHasTheSameKeys() throws {
        let english = Set(try table(for: "en").keys)
        XCTAssertFalse(english.isEmpty, "Expected the English plural table")
        for language in languages {
            XCTAssertEqual(Set(try table(for: language).keys), english,
                           "\(language).stringsdict has a different key set")
        }
    }

    func testEveryVariableDeclaresTheLanguagesCategories() throws {
        for language in languages {
            let expected = try XCTUnwrap(categories[language])
            for (key, entry) in try table(for: language) {
                let variables = entry.keys.filter { $0 != "NSStringLocalizedFormatKey" }
                XCTAssertFalse(variables.isEmpty, "\(language): \(key) has no plural variable")
                for name in variables {
                    let forms = Set((entry[name] as? [String: Any])?.keys.filter {
                        $0 != "NSStringFormatSpecTypeKey" && $0 != "NSStringFormatValueTypeKey"
                    } ?? [])
                    XCTAssertEqual(forms, expected, "\(language): \(key) (\(name)) declares \(forms)")
                    XCTAssertEqual((entry[name] as? [String: Any])?["NSStringFormatSpecTypeKey"] as? String,
                                   "NSStringPluralRuleType")
                    XCTAssertEqual((entry[name] as? [String: Any])?["NSStringFormatValueTypeKey"] as? String, "lld",
                                   "\(language): \(key) reads a %@ where the call passes an Int")
                }
            }
        }
    }

    /// Every form keeps the arguments of its key: the size, the second count
    /// and so on. Only the numeral of the plural variable itself may go, and
    /// only when the form carries no other argument (Arabic spells zero, one
    /// and two out). Foundation binds a plural form's arguments by position,
    /// so a form that drops the number *and* keeps the size hands the size to
    /// the number's slot: it prints "(null)" and then crashes.
    func testEveryFormKeepsTheArgumentsOfItsKey() throws {
        for language in languages {
            for (key, entry) in try table(for: language) {
                let variables = Set(entry.keys.filter { $0 != "NSStringLocalizedFormatKey" })
                let format = entry["NSStringLocalizedFormatKey"] as? String ?? ""
                XCTAssertEqual(format.components(separatedBy: "%#@").count - 1, variables.count,
                               "\(language): \(key) names a variable its entry does not declare")
                // The size argument may sit in the format or inside a form.
                let sizes = key.components(separatedBy: "%@").count - 1
                let formatSizes = format.components(separatedBy: "%@").count - 1
                for name in variables {
                    for (form, raw) in (entry[name] as? [String: Any]) ?? [:] where !form.hasPrefix("NSStringFormat") {
                        guard let text = raw as? String else {
                            XCTFail("\(language): \(key) (\(form)) is not a string")
                            continue
                        }
                        let formSizes = text.components(separatedBy: "%@").count - 1
                        XCTAssertEqual(formatSizes + formSizes, sizes,
                                       "\(language): \(key) (\(form)) dropped a %@ argument: \(text)")
                        if text.contains("%lld") == false {
                            let spelledOut = language == "ar"
                                && ["zero", "one", "two"].contains(form)
                                && sizes == 0
                            XCTAssertTrue(spelledOut,
                                          "\(language): \(key) (\(form)) prints no number: \(text)")
                        }
                    }
                }
            }
        }
    }
}

extension PluralTablesTests {
    private func table(for language: String) throws -> [String: [String: Any]] {
        let directory = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"),
                                      "Expected \(language).lproj in the app bundle")
        let url = URL(fileURLWithPath: directory).appendingPathComponent("Localizable.stringsdict")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: [String: Any]],
                             "\(language).stringsdict is not a plural table")
    }
}
