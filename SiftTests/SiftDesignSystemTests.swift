import AppKit
import XCTest
@testable import Sift

final class SiftDesignSystemTests: XCTestCase {
    func testBundledFamiliesRegister() {
        XCTAssertEqual(SiftFonts.registeredFamilies, [SiftFonts.ui, SiftFonts.display, SiftFonts.mono])
    }

    func testFontsResolveToTheirFamilyAtEveryWeightTheDesignUses() throws {
        for family in [SiftFonts.ui, SiftFonts.display, SiftFonts.mono] {
            for weight in [400.0, 500.0, 700.0] {
                let font = try XCTUnwrap(SiftFonts.nsFont(family, size: 13, weight: weight), "\(family) \(weight)")
                XCTAssertEqual(font.familyName, family)
                XCTAssertEqual(font.pointSize, 13)
            }
        }
    }

    func testWeightChangesTheGlyphWidths() throws {
        let regular = try XCTUnwrap(SiftFonts.nsFont(SiftFonts.ui, size: 40, weight: 400))
        let bold = try XCTUnwrap(SiftFonts.nsFont(SiftFonts.ui, size: 40, weight: 700))
        let sample = "Reclaimable 41.9 GB" as NSString
        let regularWidth = sample.size(withAttributes: [.font: regular]).width
        let boldWidth = sample.size(withAttributes: [.font: bold]).width
        XCTAssertGreaterThan(boldWidth, regularWidth)
    }

    func testUnknownFamilyFallsBackInsteadOfReturningAFont() {
        XCTAssertNil(SiftFonts.nsFont("Not A Font", size: 13, weight: 400))
    }

    func testBrassAccentIsTheDefault() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: AccentStore.defaultsKey)
        defer { defaults.set(saved, forKey: AccentStore.defaultsKey) }
        defaults.removeObject(forKey: AccentStore.defaultsKey)
        XCTAssertEqual(AccentStore.current, .brass)
        defaults.set("blue", forKey: AccentStore.defaultsKey)
        XCTAssertEqual(AccentStore.current, .blue)
    }

    func testMixInterpolatesInSRGB() throws {
        let mid = NSColor(hex: 0x000000).mixed(with: NSColor(hex: 0xFFFFFF), 0.5)
        let rgb = try XCTUnwrap(mid.usingColorSpace(.sRGB))
        XCTAssertEqual(rgb.redComponent, 0.5, accuracy: 0.001)
        XCTAssertEqual(rgb.blueComponent, 0.5, accuracy: 0.001)
    }
}
