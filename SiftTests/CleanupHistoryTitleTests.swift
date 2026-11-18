import XCTest

@testable import Sift

/// History rows stored their title as text in the language of the day
/// ("AI Apps", "System Junk", "Emptied Trash"), so the history stayed in that
/// language after a switch and never used the rail's names. The row now
/// resolves the title from the stored category — or, for records written
/// before there was one, from the old text read back through every shipped
/// language.
final class CleanupHistoryTitleTests: XCTestCase {
    func testACategoryRecordUsesTheScreensName() {
        let old = record(category: .aiApps, title: "AI Apps")
        XCTAssertEqual(CleanupHistoryTitle.text(for: old), "AI tools")

        let junk = record(category: .systemJunk, title: "System Junk")
        XCTAssertEqual(CleanupHistoryTitle.text(for: junk), "System junk")

        let installers = record(category: .installers, title: "Installers")
        XCTAssertEqual(CleanupHistoryTitle.text(for: installers), "Installers")
    }

    /// A record written in German keeps its meaning after the UI switches to
    /// English.
    func testARecordWrittenInAnotherLanguageReadsInThisOne() throws {
        let german = try translated("System Junk", in: "de")
        let stored = record(category: nil, title: german)
        XCTAssertEqual(CleanupHistoryTitle.text(for: stored), "System junk")

        let russian = try translated("AI Apps", in: "ru")
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: russian)), "AI tools")
    }

    func testTheTrashAndTheBatchTitlesKeepTheirMeaning() {
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: .trash, title: "Emptied Trash")),
                       "Emptied Trash")
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: "Emptied Trash")),
                       "Emptied Trash")
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: "Scheduled cleanup")),
                       "Scheduled cleanup")
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: "Smart Scan cleanup")),
                       "Smart Scan cleanup")
    }

    /// A title from a build this one never knew stays readable as written.
    func testAnUnknownTitleIsKeptAsWritten() {
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: "Odd one off")),
                       "Odd one off")
    }

    /// A record with neither a category nor a title — written before either
    /// existed — still has a label.
    func testAnEmptyRecordFallsBackToTheSource() {
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: nil, source: .scheduled)),
                       "Scheduled cleanup")
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: nil, source: .manual)),
                       "Smart Scan cleanup")
    }

    // MARK: - Edges

    /// Every language's own wording of a category name reads back as that
    /// category, so a history written under any of the thirteen languages
    /// keeps its meaning.
    func testEveryLanguageNamesTheSameCategory() throws {
        for language in ["ar", "de", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant"] {
            let stored = try translated("System Junk", in: language)
            XCTAssertEqual(
                CleanupHistoryTitle.text(for: record(category: nil, title: stored)),
                "System junk",
                "\(language) stored “\(stored)”")
        }
    }

    /// A category wins over text the app cannot place, and an empty string is
    /// no title at all.
    func testACategoryBeatsAnUnknownTitle() {
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: .mailAttachments, title: "Mail")),
                       "Mail files")
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: .trash, title: "")),
                       "Trash")
    }

    /// The stored title of a batch is a key now, so the row keeps saying
    /// "Scheduled cleanup" after a language switch.
    func testTheBatchKeySurvivesALanguageSwitch() throws {
        let key = try translated("Scheduled cleanup", in: "ja")
        XCTAssertEqual(CleanupHistoryTitle.text(for: record(category: nil, title: key)),
                       "Scheduled cleanup")
    }

    // MARK: - Helpers

    private func record(
        category: CleaningCategory?,
        title: String?,
        source: CleanupSource = .manual
    ) -> CleanupRecord {
        CleanupRecord(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            freedBytes: 2_000_000,
            source: source,
            title: title,
            category: category)
    }

    /// The value a key has in another language's table, i.e. what an older
    /// build stored as the record's title.
    private func translated(_ key: String, in language: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
