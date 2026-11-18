import XCTest

/// The Settings header chip used to promise that changes apply immediately,
/// while the Language row right below it says a new language needs a restart.
/// The chip now covers the common case; the copy must stay honest.
final class SettingsCopyTests: XCTestCase {
    func testHeaderChipDoesNotClaimEveryChangeAppliesImmediately() throws {
        let messages = try englishTable()

        XCTAssertEqual(
            messages["Most changes apply immediately"],
            "Most changes apply immediately",
            "Expected the Settings chip to scope its promise to most changes"
        )
    }

    /// The narrower wording stays in the tables for anyone still reading it
    /// from a cached build; keys are never deleted.
    func testTheOldChipStringKeepsItsEntry() throws {
        let messages = try englishTable()
        XCTAssertNotNil(messages["Changes apply immediately"])
    }

    func testTheChipStringIsTranslatedEverywhere() throws {
        let root = try XCTUnwrap(localizableStringsDirectory())
        let languages = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".lproj") }
        XCTAssertGreaterThanOrEqual(languages.count, 13)

        for folder in languages {
            let url = root.appendingPathComponent(folder).appendingPathComponent("Localizable.strings")
            let table = try parseStrings(at: url)
            let value = try XCTUnwrap(
                table["Most changes apply immediately"],
                "\(folder) is missing the Settings chip string"
            )
            XCTAssertFalse(value.isEmpty, "\(folder) has an empty Settings chip string")
        }
    }

    // MARK: - Helpers

    private func englishTable() throws -> [String: String] {
        let root = try XCTUnwrap(localizableStringsDirectory())
        return try parseStrings(at: root.appendingPathComponent("en.lproj/Localizable.strings"))
    }

    private func localizableStringsDirectory() -> URL? {
        if let resource = Bundle.main.resourceURL {
            let candidate = resource.appendingPathComponent("en.lproj/Localizable.strings")
            if FileManager.default.fileExists(atPath: candidate.path) { return resource }
        }
        // The app target's sources sit next to the test bundle during a local run.
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let candidate = repo.appendingPathComponent("Sift")
        return FileManager.default.fileExists(atPath: candidate.appendingPathComponent("en.lproj/Localizable.strings").path)
            ? candidate
            : nil
    }

    private func parseStrings(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
            "Expected \(url.lastPathComponent) to be a strings table"
        )
        return plist
    }
}
