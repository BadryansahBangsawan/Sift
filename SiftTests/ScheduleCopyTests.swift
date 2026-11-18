import Foundation
import XCTest
@testable import Sift

/// Settings > Schedule promises "Moves what the scan selected to the Trash".
/// An unattended clean unlinks most rows outright, so the copy has to say so.
final class ScheduleCopyTests: XCTestCase {
    func testAutoCleanCopyDoesNotPromiseATrashMove() throws {
        let english = try localizedStrings(for: "en")
        let key = "Permanently deletes the junk the scan selected, without asking"
        let copy = try XCTUnwrap(english[key])
        let lowered = copy.lowercased()

        XCTAssertFalse(
            lowered.contains("to the trash"),
            "Auto-clean unlinks most rows: the copy must not claim they go to the Trash"
        )
        XCTAssertTrue(
            lowered.contains("permanent") || lowered.contains("delete"),
            "The copy must say the rows are deleted for good"
        )
    }

    func testAutoCleanCopyExistsInEveryLanguageAndKeepsItsFormat() throws {
        let english = try localizedStrings(for: "en")
        let key = "Permanently deletes the junk the scan selected, without asking"
        XCTAssertNotNil(english[key])

        for language in ["de", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant", "ar"] {
            let strings = try localizedStrings(for: language)
            let copy = try XCTUnwrap(strings[key], "\(language) is missing the auto-clean copy")
            XCTAssertNotEqual(copy, english[key], "\(language) still carries the English sentence")
        }
    }

    func testNoLanguageStillPromisesATrashMove() throws {
        let languages = ["ar", "de", "en", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant"]
        for language in languages {
            for (key, value) in try localizedStrings(for: language) {
                XCTAssertFalse(
                    value.localizedCaseInsensitiveContains("to the Trash without asking"),
                    "\(language).lproj still claims auto-clean moves files to the Trash"
                )
                XCTAssertFalse(
                    key.localizedCaseInsensitiveContains("to the Trash without asking"),
                    "\(language).lproj still keys on the misleading sentence"
                )
            }
        }
    }

    // MARK: - Fixtures

    private func localizedStrings(for language: String) throws -> [String: String] {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = sourceRoot
            .appendingPathComponent("Sift/\(language).lproj/Localizable.strings")
        let text = try String(contentsOf: file, encoding: .utf8)
        var pairs: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""),
                  let firstQuote = trimmed.firstIndex(of: "\""),
                  let secondQuote = trimmed[trimmed.index(after: firstQuote)...].firstIndex(of: "\""),
                  let equals = trimmed[trimmed.index(after: secondQuote)...].firstIndex(of: "="),
                  let thirdQuote = trimmed[trimmed.index(after: equals)...].firstIndex(of: "\""),
                  let fourthQuote = trimmed[trimmed.index(after: thirdQuote)...].firstIndex(of: "\"")
            else { continue }
            let key = String(trimmed[trimmed.index(after: firstQuote)..<secondQuote])
            let value = String(trimmed[trimmed.index(after: thirdQuote)..<fourthQuote])
            pairs[key] = value
        }
        return pairs
    }
}
