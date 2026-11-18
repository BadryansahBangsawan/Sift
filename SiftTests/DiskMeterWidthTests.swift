import AppKit
import SwiftUI
import XCTest
@testable import Sift

/// A storage capsule must show what it means: its label and its value, in full.
/// A translated label that ends in an ellipsis leaves the colour unexplained.
@MainActor
final class DiskMeterWidthTests: XCTestCase {
    private let languages = ["ar", "de", "en", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant"]

    func testEveryLanguageShowsItsCapsuleLabelsInFull() throws {
        let meter = DiskMeterLayout.meterWidth(atWindowWidth: 1080)
        XCTAssertGreaterThan(meter, 0)

        for language in languages {
            let strings = try localizedStrings(for: language)
            let label = try XCTUnwrap(strings["Reclaimable"], "\(language) has no Reclaimable label")
            let freeFormat = try XCTUnwrap(strings["%@ free"], "\(language) has no free-space label")
            let value = SiftFormat.bytes(28_480_000_000)
            let freeText = freeFormat.replacingOccurrences(of: "%@", with: value)

            let labelWidth = measure(label, font: labelFont)
            let valueWidth = measure(value, font: valueFont)
            let freeWidth = measure(freeText, font: valueFont)

            let widths = DiskMeterLayout.segmentWidths(
                total: meter - DiskMeterLayout.spacing * 2,
                disk: 494_000_000_000,
                freeSpace: 28_480_000_000,
                reclaimable: 41_200_000_000,
                labelWidth: labelWidth,
                valueWidth: valueWidth,
                freeTextWidth: freeWidth,
                freeLongestWordWidth: DiskMeterLayout.longestWordWidth(freeText) {
                    self.measure($0, font: self.valueFont)
                }
            )
            let junkWidth = try XCTUnwrap(widths.reclaimable)
            let style = DiskMeterLayout.style(width: junkWidth, label: labelWidth, value: valueWidth)
            XCTAssertGreaterThanOrEqual(
                junkWidth,
                requiredWidth(style: style, label: labelWidth, value: valueWidth),
                "\(language) “\(label)” needs \(Int(requiredWidth(style: style, label: labelWidth, value: valueWidth))) pt in a \(Int(junkWidth)) pt capsule"
            )

            let limit = DiskMeterLayout.freeLineLimit(textWidth: freeWidth, available: widths.free)
            let freeRequired = limit == 1
                ? freeWidth + DiskMeterLayout.capsulePadding * 2
                : DiskMeterLayout.longestWordWidth(freeText) { measure($0, font: self.valueFont) } + DiskMeterLayout.capsulePadding * 2
            XCTAssertGreaterThanOrEqual(
                widths.free,
                freeRequired,
                "\(language) “\(freeText)” needs \(Int(freeRequired)) pt in a \(Int(widths.free)) pt capsule"
            )
        }
    }

    // MARK: - Edge cases

    func testALargeSlicePutsTheLabelAndValueBackOnOneLine() throws {
        let strings = try localizedStrings(for: "ru")
        let label = try XCTUnwrap(strings["Reclaimable"])
        let value = SiftFormat.bytes(300_000_000_000)
        let freeText = (strings["%@ free"] ?? "%@ free").replacingOccurrences(of: "%@", with: SiftFormat.bytes(300_000_000_000))

        // A slice that is a large share of the disk gets room for one line.
        let meter = DiskMeterLayout.meterWidth(atWindowWidth: 1_600)
        let widths = DiskMeterLayout.segmentWidths(
            total: meter - DiskMeterLayout.spacing * 2,
            disk: 494_000_000_000,
            freeSpace: 300_000_000_000,
            reclaimable: 300_000_000_000,
            labelWidth: measure(label, font: labelFont),
            valueWidth: measure(value, font: valueFont),
            freeTextWidth: measure(freeText, font: valueFont),
            freeLongestWordWidth: DiskMeterLayout.longestWordWidth(freeText) { self.measure($0, font: self.valueFont) }
        )

        let junkWidth = try XCTUnwrap(widths.reclaimable)
        XCTAssertEqual(
            DiskMeterLayout.style(width: junkWidth, label: measure(label, font: labelFont), value: measure(value, font: valueFont)),
            .inline,
            "A wide slice keeps one line; stacking is the fallback for a narrow one"
        )
        XCTAssertEqual(
            DiskMeterLayout.freeLineLimit(textWidth: measure(freeText, font: valueFont), available: widths.free),
            1
        )
    }

    func testTheTwoCapsulesNeverTakeTheWholeBar() {
        for windowWidth in stride(from: 1_080.0, through: 1_600.0, by: 40) {
            let meter = DiskMeterLayout.meterWidth(atWindowWidth: CGFloat(windowWidth))
            let available = DiskMeterLayout.available(total: meter - DiskMeterLayout.spacing * 2, hasReclaimable: true)
            let widths = DiskMeterLayout.segmentWidths(
                total: meter - DiskMeterLayout.spacing * 2,
                disk: 494_000_000_000,
                freeSpace: 400_000_000_000,
                reclaimable: 60_000_000_000,
                labelWidth: 108,
                valueWidth: 60,
                freeTextWidth: 143,
                freeLongestWordWidth: 62
            )
            let junk = widths.reclaimable ?? 0
            XCTAssertLessThanOrEqual(
                junk + widths.free,
                available,
                "At \(Int(windowWidth)) pt the capsules overflow the bar"
            )
            XCTAssertGreaterThan(available - junk - widths.free, 0, "The in-use capsule keeps room at \(Int(windowWidth)) pt")
        }
    }

    // MARK: - Fixtures

    private var labelFont: NSFont { SiftFonts.nsFont(SiftFonts.ui, size: 11, weight: 500) ?? .systemFont(ofSize: 11, weight: .medium) }
    private var valueFont: NSFont { SiftFonts.nsFont(SiftFonts.display, size: 16, weight: 400) ?? .systemFont(ofSize: 16) }

    private func requiredWidth(style: DiskMeterLayout.Style, label: CGFloat, value: CGFloat) -> CGFloat {
        switch style {
        case .inline: return DiskMeterLayout.inlineWidth(label: label, value: value)
        case .stacked: return DiskMeterLayout.stackedWidth(label: label, value: value)
        }
    }

    private func measure(_ text: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
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
