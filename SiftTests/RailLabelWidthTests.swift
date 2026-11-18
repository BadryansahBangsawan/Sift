import AppKit
import SwiftUI
import XCTest
@testable import Sift

/// Rail items are the app's navigation. A translated label that ends in an
/// ellipsis hides where the row goes, so every language must fit in full.
@MainActor
final class RailLabelWidthTests: XCTestCase {
    private let languages = ["ar", "de", "en", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant"]

    func testEveryRailLabelFitsInFull() throws {
        let width = SiftSpacing.railWidth
        let card = RailRowLayout.labelWidth(railWidth: width, trailingWidth: badgeWidth)
        XCTAssertGreaterThan(card, 0)

        for language in languages {
            let strings = try localizedStrings(for: language)
            let labels = strings.filter { Self.railKeys.contains($0.key) }.map(\.value)
            XCTAssertFalse(labels.isEmpty, "\(language) has no rail labels")

            for label in labels {
                let ideal = measure(label)
                let limit = RailRowLayout.lineLimit(labelWidth: ideal, available: card)
                let lines = lineCount(label, width: card)
                XCTAssertLessThanOrEqual(
                    lines, limit,
                    "\(language) “\(label) at \(Int(ideal)) pt is clipped into \(lines) line(s) in a \(Int(card)) pt column"
                )
            }
        }
    }

    func testShortLabelsKeepOneLineAndTheRowKeepsItsHeight() {
        let card = RailRowLayout.labelWidth(railWidth: SiftSpacing.railWidth, trailingWidth: badgeWidth)
        XCTAssertEqual(RailRowLayout.lineLimit(labelWidth: 60, available: card), 1)
        XCTAssertEqual(
            RailRowLayout.rowMinHeight, 36,
            "Rows without a badge keep the rail's rhythm; wrapping grows the row, never shrinks it"
        )
        XCTAssertGreaterThan(card, 100, "A rail row must still leave a usable label column")
    }

    // MARK: - Fixtures

    /// A row with a count badge is the widest case: the badge takes the most room.
    private var badgeWidth: CGFloat { 34 }
    private static let railKeys: Set<String> = [
        "Overview", "System junk", "Leftovers", "Large & old files", "Project junk",
        "Scheduled cleanup", "Settings",
    ]

    /// Lines the label lays out in at `width`; wrapping is per word, and per
    /// character for scripts without spaces.
    private func lineCount(_ text: String, width: CGFloat) -> Int {
        let font = SiftFonts.nsFont(SiftFonts.ui, size: 13, weight: 400) ?? .systemFont(ofSize: 13)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var start = 0
        var lines = 0
        while start < attributed.length {
            let consumed = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard consumed > 0 else { return Int.max }
            start += consumed
            lines += 1
            if lines > 3 { return lines }
        }
        return lines
    }

    private func measure(_ text: String) -> CGFloat {
        let font = SiftFonts.nsFont(SiftFonts.ui, size: 13, weight: 400) ?? .systemFont(ofSize: 13)
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    private func localizedStrings(for language: String) throws -> [String: String] {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = sourceRoot.appendingPathComponent("Sift/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: file)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(plist as? [String: String])
    }
}
