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

    private func literalKeys() throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sift")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var keys = Set<String>()
        for case let url as URL in files where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            for pattern in patterns {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(source.startIndex..., in: source)
                for match in regex.matches(in: source, range: range) {
                    guard let captured = Range(match.range(at: 1), in: source) else { continue }
                    let key = String(source[captured])
                    // Interpolated strings are checked by their plural key in
                    // `LocalizationPluralCoverageTests`; bare separators ("·",
                    // ", ") are punctuation, not copy.
                    if key.contains("\\(") || key.rangeOfCharacter(from: .letters) == nil {
                        continue
                    }
                    keys.insert(key)
                }
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
