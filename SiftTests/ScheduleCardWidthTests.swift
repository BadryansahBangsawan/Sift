import AppKit
import SwiftUI
import XCTest

@testable import Sift

/// The rail's schedule card is one row of text beside a switch. QA6 let the
/// labels wrap, which turned the English card into "Scheduled" / "scan" /
/// "Off" on three lines at a 1360 pt window: a title that fits must stay on
/// one line, and only a title that really does not fit may take a second.
@MainActor
final class ScheduleCardWidthTests: XCTestCase {
    private let languages = ["ar", "de", "en", "es", "fr", "it", "ja", "pl",
                             "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant"]

    func testEnglishKeepsOneLineAndLongTitlesWrap() {
        let column = ScheduleCardLayout.columnWidth(railWidth: SiftSpacing.railWidth)
        XCTAssertGreaterThan(column, 0)

        let english = ScheduleCardLayout.width(of: "Scheduled cleanup", size: 10.5)
        XCTAssertLessThanOrEqual(english, column, "The English title fits the column")
        XCTAssertEqual(
            ScheduleCardLayout.lineLimit(labelWidth: english, available: column), 1,
            "A title that fits must stay on one line")

        let long = ScheduleCardLayout.width(
            of: "Scheduled cleanup on the second Tuesday of every month", size: 10.5)
        XCTAssertGreaterThan(long, column, "A long title does not fit and must wrap")
        XCTAssertEqual(ScheduleCardLayout.lineLimit(labelWidth: long, available: column), 2)
    }

    func testEveryLanguageDecidesByItsOwnWidth() throws {
        let column = ScheduleCardLayout.columnWidth(railWidth: SiftSpacing.railWidth)
        for language in languages {
            for key in ["Scheduled scan", "Scheduled cleanup"] {
                let title = try localized(key, in: language)
                let ideal = ScheduleCardLayout.width(of: title, size: 10.5)
                let limit = ScheduleCardLayout.lineLimit(labelWidth: ideal, available: column)
                if ideal <= column {
                    XCTAssertEqual(limit, 1,
                                   "\(language) “\(title)” fits in \(Int(column)) pt and must not wrap")
                } else {
                    XCTAssertEqual(limit, 2,
                                   "\(language) “\(title)” needs \(Int(ideal)) pt and must wrap")
                }
            }
        }
    }

    // MARK: - Wrapping and the status line

    /// A title too wide for the column takes two lines and can break at a
    /// space: no single word may be wider than the column, or the second line
    /// would clip instead of wrapping.
    func testLongTitlesWrapWithoutClipping() throws {
        let column = ScheduleCardLayout.columnWidth(railWidth: SiftSpacing.railWidth)
        let breakable = ["de", "es", "fr", "it", "pl", "pt-BR", "ru", "uk", "ar", "en"]
        var wrapped = 0
        for language in breakable {
            for key in ["Scheduled scan", "Scheduled cleanup"] {
                let title = try localized(key, in: language)
                let ideal = ScheduleCardLayout.width(of: title, size: 10.5)
                guard ideal > column else { continue }
                wrapped += 1
                XCTAssertEqual(ScheduleCardLayout.lineLimit(labelWidth: ideal, available: column), 2,
                               "\(language) “\(title)” must wrap")
                let widest = title.split(separator: " ")
                    .map { ScheduleCardLayout.width(of: String($0), size: 10.5) }
                    .max() ?? 0
                XCTAssertLessThanOrEqual(
                    widest, column,
                    "\(language) “\(title)” has a \(Int(widest)) pt word in a \(Int(column)) pt column")
            }
        }
        XCTAssertGreaterThan(wrapped, 4, "Expected several languages to wrap")
    }

    /// The status word under the title keeps its own line in every language,
    /// so a wrapped title never hides "Off" or "Daily".
    func testTheStatusLineFitsOneLine() throws {
        let column = ScheduleCardLayout.columnWidth(railWidth: SiftSpacing.railWidth)
        for language in languages {
            for key in ["Off", "Daily", "Weekly"] {
                let status = try localized(key, in: language)
                XCTAssertLessThanOrEqual(
                    ScheduleCardLayout.width(of: status, size: 12.5), column,
                    "\(language) status “\(status)” does not fit")
            }
        }
    }

    // MARK: - Fixtures

    private func localized(_ key: String, in language: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sift/\(language).lproj/Localizable.strings")
        let text = try String(contentsOf: path, encoding: .utf8)
        let pattern = try NSRegularExpression(
            pattern: "^\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*=\\s*\"(.*)\";$",
            options: [.anchorsMatchLines])
        let range = NSRange(text.startIndex..., in: text)
        let match = try XCTUnwrap(pattern.firstMatch(in: text, range: range), "\(language) has no “\(key)”")
        let value = try XCTUnwrap(Range(match.range(at: 1), in: text))
        return String(text[value])
    }
}
