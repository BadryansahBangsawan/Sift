import AppKit
import SwiftUI
import XCTest

@testable import Sift

/// The Uninstaller footer has to show what is about to be removed. It used to
/// lose that fight to the buttons next to it: at the 1080 pt window the
/// summary collapsed to a few points and the user saw one clipped glyph
/// between "Dry run" and "Review removal". The summary now has a line of its
/// own above the buttons, in every language, and these tests render the real
/// footer to prove it is drawn in full.
@MainActor
final class UninstallerActionBarTests: XCTestCase {
    /// The card is padded 24 pt on both sides.
    private let barWidth: CGFloat = 1080 - 2 * 24
    private let barHeight: CGFloat = 60
    private let sizeText = "1,12 GB"

    func testEveryLanguageDrawsItsSummaryInFull() throws {
        var checked = 0
        for language in AppLanguage.allCases.map(\.rawValue) where language != "system" {
            let bundle = try localizationBundle(for: language)
            let locale = Locale(identifier: language)
            // The widest number the summary can carry: a long count in a
            // language whose words for it are long.
            let text = String(localized: "\(25) items, \(sizeText)", bundle: bundle, locale: locale)
            let ink = drawnSummaryInk(text, width: barWidth)
            let ideal = idealWidth(text)
            XCTAssertGreaterThan(ideal, 0, "\(language) produced no summary")
            XCTAssertGreaterThanOrEqual(
                ink.width, ideal - 5,
                "\(language) “\(text)” drew \(Int(ink.width)) pt of its \(Int(ideal)) pt")
            XCTAssertGreaterThanOrEqual(
                ink.maxX, barWidth - 30, "\(language) “\(text)” is not right-aligned")
            checked += 1
        }
        XCTAssertEqual(checked, 13, "Every shipped language must be covered")
    }

    func testTheSummarySitsAtTheTrailingEdgeOfItsLine() {
        let ink = drawnSummaryInk("25 items, 1.12 GB", width: barWidth)
        XCTAssertGreaterThanOrEqual(ink.maxX, barWidth - 30)
        XCTAssertGreaterThan(ink.width, 0)
    }

    // MARK: - Plural forms

    /// The bar takes a `Text` built from the plural key, so SwiftUI picks the
    /// form for the number: never "1 items" in any language.
    func testCountsAgreeWithTheirNumber() throws {
        XCTAssertEqual(try count(1, "en"), "1 item, \(sizeText)")
    }

    func testCountsAgreeWithTheirNumberDE() throws {
        XCTAssertEqual(try count(1, "de"), "1 Element, \(sizeText)")
        XCTAssertEqual(try count(2, "de"), "2 Elemente, \(sizeText)")
        XCTAssertEqual(try count(1, "ru"), "1 объект, \(sizeText)")
        XCTAssertEqual(try count(2, "ru"), "2 объекта, \(sizeText)")
        XCTAssertEqual(try count(5, "ru"), "5 объектов, \(sizeText)")
        XCTAssertEqual(try count(1, "pl"), "1 element, \(sizeText)")
        XCTAssertEqual(try count(3, "pl"), "3 elementy, \(sizeText)")
        XCTAssertEqual(try count(12, "pl"), "12 elementów, \(sizeText)")
    }

    func testCountsAgreeWithTheirNumberAR() throws {
        XCTAssertEqual(try count(1, "ar"), "عنصر واحد، \(sizeText)")
        XCTAssertEqual(try count(2, "ar"), "عنصران، \(sizeText)")
        XCTAssertEqual(try count(5, "ar"), "5 عناصر، \(sizeText)")
    }

    /// A one-file selection renders the singular, so the footer never says
    /// "1 items" when it is built the way the Uninstaller builds it.
    func testTheUninstallerBuildsTheSummaryFromThePluralKey() {
        XCTAssertEqual(String(localized: "\(1) items, \(sizeText)"), "1 item, \(sizeText)")
        XCTAssertFalse(
            String(localized: "\(1) items, \(sizeText)").contains("items"),
            "The footer's own sentence must pluralise")
    }

    // MARK: - Helpers

    private func count(_ n: Int, _ language: String) throws -> String {
        let bundle = try localizationBundle(for: language)
        return String(localized: "\(n) items, \(sizeText)", bundle: bundle, locale: Locale(identifier: language))
    }

    private func localizationBundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "Expected \(language).lproj in the built app bundle"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    // MARK: - Rendering

    private func bar(summary: Text) -> some View {
        UninstallerActionBar(
            summary: summary,
            canDryRun: true,
            canReview: true,
            runningAppName: nil,
            showInFinder: {},
            dryRun: {},
            review: {}
        )
    }

    private func bitmap(summary: Text, width: CGFloat) -> NSBitmapImageRep {
        let content = bar(summary: summary)
            .frame(width: width, height: barHeight)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(content))
        host.frame = NSRect(x: 0, y: 0, width: width, height: barHeight)
        host.layoutSubtreeIfNeeded()
        // SwiftUI settles on its first layout in a run-loop turn; without this
        // a fresh hosting view can rasterize blank.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not rasterize the footer")
            return NSBitmapImageRep()
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    /// The summary's own line is the top band: the buttons start below it.
    private var summaryBand: Range<Int> { 0..<18 }

    private struct Ink {
        var minX: CGFloat
        var maxX: CGFloat
        var width: CGFloat { maxX - minX }
    }

    private func drawnSummaryInk(_ text: String, width: CGFloat) -> Ink {
        let rep = bitmap(summary: Text(verbatim: text), width: width)
        let scale = CGFloat(rep.pixelsWide) / max(1, width)
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX: CGFloat = 0
        for y in summaryBand {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let luma = (color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255
                guard luma > 30 else { continue }
                minX = min(minX, CGFloat(x) / scale)
                maxX = max(maxX, CGFloat(x) / scale)
            }
        }
        guard minX < .greatestFiniteMagnitude else { return Ink(minX: 0, maxX: 0) }
        return Ink(minX: minX, maxX: maxX)
    }

    private func idealWidth(_ text: String) -> CGFloat {
        let font = SiftFonts.nsFont(SiftFonts.mono, size: 12, weight: 400)
            ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        return ceil(attributed.size().width)
    }
}
