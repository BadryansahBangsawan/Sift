import Foundation
import XCTest
@testable import Sift

/// Settings > Schedule describes what an unattended clean does. It moves the
/// selection to the Trash, so the copy must say so and must not promise a
/// permanent delete.
final class ScheduleCopyTests: XCTestCase {
    private let key = "Moves the junk the scan selected to the Trash, without asking"

    func testScheduledNotificationAboveThresholdIsUnchanged() {
        let body = AppState.scheduledNotificationBody(
            found: 10_000,
            selectedSize: 10_000,
            autoClean: true,
            minimumCleanSize: 5_000
        )

        XCTAssertTrue(body.contains("Found"), body)
        XCTAssertFalse(body.localizedCaseInsensitiveContains("nothing was removed"), body)
    }

    func testSuppressedNotificationExistsInEveryLanguage() throws {
        let key = "Found %@ of junk files, below the cleanup threshold. Nothing was removed."
        let english = try localizedStrings(for: "en")
        let englishCopy = try XCTUnwrap(english[key])

        for language in ["de", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant", "ar"] {
            let strings = try localizedStrings(for: language)
            let copy = try XCTUnwrap(strings[key], "\(language) is missing the skipped-clean notification")
            XCTAssertNotEqual(copy, englishCopy, "\(language) still carries the English sentence")
            XCTAssertTrue(copy.contains("%@"), "\(language) lost the size placeholder")
        }
    }

    func testSuppressedScheduledCleanNotificationSaysNothingWasRemoved() {
        let body = AppState.scheduledNotificationBody(
            found: 10_000,
            selectedSize: 100,
            autoClean: true,
            minimumCleanSize: 5_000
        )

        XCTAssertTrue(
            body.localizedCaseInsensitiveContains("nothing was removed"),
            "a clean suppressed by the minimum size must say so, got: \(body)"
        )
        XCTAssertFalse(body.localizedCaseInsensitiveContains("cleaned"), body)
    }

    func testAutoCleanCopyPromisesATrashMove() throws {
        let english = try localizedStrings(for: "en")
        let copy = try XCTUnwrap(english[key])
        let lowered = copy.lowercased()

        XCTAssertTrue(
            lowered.contains("to the trash"),
            "A scheduled clean now moves every row to the Trash: the copy must say so"
        )
        XCTAssertFalse(
            lowered.contains("permanent") || lowered.contains("delete"),
            "The copy must not claim the rows are deleted for good"
        )
    }

    func testAutoCleanCopyExistsInEveryLanguageAndKeepsItsFormat() throws {
        let english = try localizedStrings(for: "en")
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
