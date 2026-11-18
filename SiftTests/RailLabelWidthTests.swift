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
                if limit == 1 {
                    XCTAssertLessThanOrEqual(
                        ideal, card,
                        "\(language) “\(label)” is \(Int(ideal)) pt in a \(Int(card)) pt column and would be clipped"
                    )
                } else {
                    let word = label.split(separator: " ").map { measure(String($0)) }.max() ?? 0
                    XCTAssertLessThanOrEqual(
                        word, card,
                        "\(language) “\(label)” cannot wrap: its longest word is \(Int(word)) pt"
                    )
                }
            }
        }
    }

    // MARK: - Fixtures

    /// A row with a count badge is the widest case: the badge takes the most room.
    private var badgeWidth: CGFloat { 34 }
    private static let railKeys: Set<String> = [
        "Overview", "System junk", "Leftovers", "Large & old files", "Project junk",
        "Scheduled cleanup", "Settings",
    ]

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
