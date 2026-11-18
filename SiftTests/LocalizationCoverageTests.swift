import XCTest

/// Every literal the UI shows has to exist in all thirteen tables. The
/// Leftovers rework shipped "No Leftovers" and "Scan for leftover files" with
/// no translation at all, so twelve languages said it in English.
final class LocalizationCoverageTests: XCTestCase {
    private let languages = ["en", "de", "es", "fr", "it", "ja", "pl",
                             "pt-BR", "ru", "uk", "ar", "zh-Hans", "zh-Hant"]

    /// Call sites whose first string argument is shown to the user.
    private let patterns = [
        #"\b(?:Text|Button|Label|LocalizedStringKey|ProgressView)\(\s*"([^"\n]+)""#,
        #"\bString\(localized:\s*"([^"\n]+)""#,
        #"\b(?:actionLabel|description|title|subtitle|eyebrow|placeholder)\s*:\s*"([^"\n]+)""#,
        #"\.(?:help|navigationTitle|alert|confirmationDialog|accessibilityLabel)\(\s*"([^"\n]+)""#,
        #"EmptyStateView\(\s*"([^"\n]+)""#,
    ]

    func testEveryLiteralUIStringIsTranslated() throws {
        let keys = try literalKeys()
        XCTAssertGreaterThan(keys.count, 500, "The scan found too few strings to be meaningful")

        var failures: [String: [String]] = [:]
        for language in languages {
            let tables = try tables(for: language)
            let missing = keys.filter { tables.strings[$0] == nil && tables.plurals[$0] == nil }
            if !missing.isEmpty { failures[language] = missing.sorted() }
        }
        XCTAssertTrue(
            failures.isEmpty,
            failures
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.joined(separator: " | "))" }
                .joined(separator: "\n"))
    }

    // MARK: - Source scan

    /// Every app source file, read once per scan.
    private func sources() throws -> [(source: String, url: URL)] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sift")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var out: [(String, URL)] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            out.append((try String(contentsOf: url, encoding: .utf8), url))
        }
        return out
    }

    private func literalKeys() throws -> Set<String> {
        var keys = Set<String>()
        for (source, _) in try sources() {
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(source.startIndex..., in: source)
                for match in regex.matches(in: source, range: range) {
                    guard let captured = Range(match.range(at: 1), in: source) else { continue }
                    let key = String(source[captured])
                    // Interpolated strings are checked by their plural key in
                    // `testInterpolatedCopyResolvesInEveryLanguage`; bare
                    // separators ("·", ", ") are punctuation, not copy.
                    if key.contains("\\(") || key.rangeOfCharacter(from: .letters) == nil {
                        continue
                    }
                    keys.insert(key)
                }
            }
        }
        return keys
    }

    // MARK: - Interpolated copy

    /// A literal built with interpolation becomes a format key: `"\(n) items"`
    /// is `%lld items`. Those keys live in the stringsdict, and they must exist
    /// in every language, not just the one that wrote them.
    func testInterpolatedCopyResolvesInEveryLanguage() throws {
        let english = try tables(for: "en")
        let derived = try interpolatedKeys()
        let plurals = derived.filter { english.plurals[$0] != nil }
        XCTAssertGreaterThan(plurals.count, 5, "Expected several plural-backed literals")

        for language in languages where language != "en" {
            let tables = try tables(for: language)
            for key in plurals.sorted() {
                XCTAssertNotNil(tables.plurals[key], "\(language) has no entry for “\(key)”")
            }
        }
    }

    /// A key that one language lacks is reported against that language, so a
    /// missing table names itself instead of "something is missing".
    func testAMissingEntryNamesItsLanguage() throws {
        let keys: Set<String> = ["No Leftovers", "Only This Test Knows It"]
        let english = try tables(for: "en")
        let german = try tables(for: "de")
        XCTAssertEqual(missing(keys, in: german), ["Only This Test Knows It"])
        XCTAssertEqual(missing(keys, in: english), ["Only This Test Knows It"])
    }

    private func missing(_ keys: Set<String>, in tables: Tables) -> [String] {
        keys.filter { tables.strings[$0] == nil && tables.plurals[$0] == nil }.sorted()
    }

    /// Every interpolated literal, with each `\(…)` replaced by `%lld`: the
    /// shape the tables use for a count.
    private func interpolatedKeys() throws -> Set<String> {
        var keys = Set<String>()
        for (source, _) in try sources() {
            let regex = try NSRegularExpression(
                pattern: #"\b(?:Text|Button|Label|LocalizedStringKey)\(\s*"([^"\n]*\\\([^"\n]*)"#)
            let range = NSRange(source.startIndex..., in: source)
            for match in regex.matches(in: source, range: range) {
                guard let captured = Range(match.range(at: 1), in: source) else { continue }
                var key = String(source[captured])
                key = key.replacingOccurrences(
                    of: #"\\\([^)]*\)"#, with: "%lld", options: .regularExpression)
                if key.rangeOfCharacter(from: .letters) != nil { keys.insert(key) }
            }
        }
        return keys
    }

    private struct Tables {
        var strings: [String: String]
        var plurals: [String: Any]
    }

    private func tables(for language: String) throws -> Tables {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sift/\(language).lproj")

        let stringsText = try String(
            contentsOf: root.appendingPathComponent("Localizable.strings"), encoding: .utf8)
        let line = try NSRegularExpression(pattern: #"^"((?:[^"\\]|\\.)*)"\s*=\s*"(.*)";$"#)
        var strings: [String: String] = [:]
        for row in stringsText.split(separator: "\n") {
            let text = String(row)
            let range = NSRange(text.startIndex..., in: text)
            guard let match = line.firstMatch(in: text, range: range),
                  let key = Range(match.range(at: 1), in: text),
                  let value = Range(match.range(at: 2), in: text) else { continue }
            strings[String(text[key])] = String(text[value])
        }

        let data = try Data(contentsOf: root.appendingPathComponent("Localizable.stringsdict"))
        let plurals = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        return Tables(strings: strings, plurals: plurals)
    }
}
