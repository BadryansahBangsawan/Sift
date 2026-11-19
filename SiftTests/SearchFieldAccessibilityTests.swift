import XCTest

@testable import Sift

/// The cleanup list carried one label for the whole control ("Filter cleanup
/// files"), so VoiceOver read the field and its × button as the same thing.
/// Each control now has its own name, and both come from the shipped tables.
final class SearchFieldAccessibilityTests: XCTestCase {
    private let promptKeys = ["Filter by name or path", "Search applications"]
    private let languages = ["en", "de", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "ar", "zh-Hans", "zh-Hant"]

    func testTheClearButtonIsNeverNamedLikeAFieldsPrompt() throws {
        XCTAssertEqual(SearchFieldLabels.clear, "Clear search")
        for language in languages {
            let bundle = try bundle(for: language)
            let clear = bundle.localizedString(forKey: "Clear search", value: nil, table: nil)
            XCTAssertFalse(clear.isEmpty, "\(language) has no clear-button label")
            for key in promptKeys {
                let prompt = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertFalse(prompt.isEmpty, "\(language) has no prompt for “\(key)”")
                XCTAssertNotEqual(clear, prompt,
                                  "\(language): the field and its clear button share “\(clear)”")
            }
        }
    }

    /// The field is announced by its prompt, not by a label glued onto the
    /// whole control.
    func testTheFieldTakesItsNameFromItsPrompt() throws {
        for language in ["en", "de"] {
            let bundle = try bundle(for: language)
            let prompt = bundle.localizedString(forKey: "Filter by name or path", value: nil, table: nil)
            let labels = SearchFieldLabels(field: prompt)
            XCTAssertEqual(labels.field, prompt)
            XCTAssertNotEqual(labels.field, SearchFieldLabels.clear)
        }
    }

    /// German is the case where the two sentences are longest: both labels
    /// must still be there, and neither may fall back to English.
    func testGermanKeepsBothLabels() throws {
        let de = try bundle(for: "de")
        let prompt = de.localizedString(forKey: "Filter by name or path", value: nil, table: nil)
        let uninstaller = de.localizedString(forKey: "Search applications", value: nil, table: nil)
        let clear = de.localizedString(forKey: "Clear search", value: nil, table: nil)
        XCTAssertNotEqual(clear, "Clear search", "German fell back to English for the clear button")
        XCTAssertNotEqual(prompt, "Filter by name or path")
        XCTAssertNotEqual(uninstaller, "Search applications")
        XCTAssertNotEqual(clear, prompt)
        XCTAssertNotEqual(clear, uninstaller)
        XCTAssertEqual(SearchFieldLabels(field: uninstaller).field, uninstaller)
    }

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }
}
