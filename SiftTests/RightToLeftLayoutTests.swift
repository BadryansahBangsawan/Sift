import AppKit
import SwiftUI
import XCTest
@testable import Sift

/// Arabic is the one right-to-left language Sift ships. macOS gives a SwiftUI
/// app the system's interface direction, not its own localization, so every
/// scene sets the direction itself; these tests hold the shell, the icons and
/// the hand-drawn bars to it.
@MainActor
final class RightToLeftLayoutTests: XCTestCase {
    // MARK: - Root direction

    func testArabicResolvesToARightToLeftRoot() {
        XCTAssertEqual(AppLayoutDirection.direction(for: ["ar"]), .rightToLeft)
        XCTAssertEqual(AppLayoutDirection.direction(for: ["ar-SA"]), .rightToLeft)
        XCTAssertEqual(
            AppLayoutDirection.direction(for: ["ar", "en"]), .rightToLeft,
            "The first localization the bundle resolves is the one on screen"
        )
    }

    func testTheOtherShippedLanguagesStayLeftToRight() {
        for language in ["de", "en", "es", "fr", "it", "ja", "pl", "pt-BR", "ru", "uk", "zh-Hans", "zh-Hant"] {
            XCTAssertEqual(AppLayoutDirection.direction(for: [language]), .leftToRight, language)
        }
        XCTAssertEqual(AppLayoutDirection.direction(for: []), .leftToRight)
    }

    // MARK: - Shell

    /// The window is a rail and a detail pane. Applying the direction the way
    /// `SiftApp` does must float the rail on the right for Arabic.
    func testTheWindowRootPutsTheRailOnTheRightInArabic() {
        let rtl = render(twoPaneShell.siftLayoutDirection(.rightToLeft), size: CGSize(width: 240, height: 40))
        let ltr = render(twoPaneShell.siftLayoutDirection(.leftToRight), size: CGSize(width: 240, height: 40))

        let railRTL = inkBounds(rtl) { $0.redComponent > 0.9 && $0.greenComponent < 0.2 }
        let railLTR = inkBounds(ltr) { $0.redComponent > 0.9 && $0.greenComponent < 0.2 }

        XCTAssertGreaterThanOrEqual(railRTL.minX, 199, "The rail pane stays on the left in Arabic")
        XCTAssertLessThanOrEqual(railLTR.maxX, 41, "The rail pane moved off the left edge in English")
    }

    // MARK: - Icons

    /// A disclosure chevron points along the reading order, so Arabic shows it
    /// turned the other way.
    func testTheDisclosureChevronTurnsInArabic() {
        let ltr = render(chevron, size: CGSize(width: 16, height: 16), direction: .leftToRight)
        let rtl = render(chevron, size: CGSize(width: 16, height: 16), direction: .rightToLeft)

        let ltrCenter = inkCenterX(ltr)
        let rtlCenter = inkCenterX(rtl)
        XCTAssertLessThan(
            rtlCenter, ltrCenter - 0.5,
            "The chevron still points right in Arabic (\(Int(rtlCenter)) pt vs \(Int(ltrCenter)) pt)"
        )
    }

    // MARK: - Bars

    /// Progress fills from the leading edge, which is the right in Arabic.
    func testTheMeterFillsFromTheRightInArabic() {
        let rtl = render(meter, size: CGSize(width: 200, height: 6), direction: .rightToLeft)
        let filled = inkBounds(rtl) { $0.redComponent > 0.8 && $0.greenComponent < 0.2 }
        XCTAssertGreaterThanOrEqual(filled.minX, 139, "A quarter-full meter still fills from the left in Arabic")
        XCTAssertEqual(filled.width, 50, accuracy: 2)
    }

    // MARK: - Custom layout

    /// `WhereRowLayout.Row` places its five columns by hand, so it must read
    /// the direction itself: the icon column goes on the right in Arabic.
    func testTheWhereRowPutsItsIconColumnOnTheRightInArabic() {
        let rtl = render(whereRow(direction: .rightToLeft), size: CGSize(width: 300, height: 40))
        let icon = inkBounds(rtl) { $0.redComponent > 0.9 && $0.greenComponent < 0.2 }
        XCTAssertGreaterThanOrEqual(icon.minX, 267, "The icon column stayed on the left in Arabic")

        let ltr = render(whereRow(direction: .leftToRight), size: CGSize(width: 300, height: 40))
        let iconLTR = inkBounds(ltr) { $0.redComponent > 0.9 && $0.greenComponent < 0.2 }
        XCTAssertLessThanOrEqual(iconLTR.maxX, 33)
    }

    // MARK: - Edge cases

    func testDirectionCoversIdentifiersASystemCanReport() {
        XCTAssertEqual(AppLayoutDirection.direction(forLanguage: "AR"), .rightToLeft)
        XCTAssertEqual(AppLayoutDirection.direction(forLanguage: "ar-EG"), .rightToLeft)
        XCTAssertEqual(AppLayoutDirection.direction(forLanguage: "ar_SA"), .rightToLeft)
        XCTAssertEqual(AppLayoutDirection.direction(forLanguage: "he"), .rightToLeft)
        XCTAssertEqual(AppLayoutDirection.direction(forLanguage: "zh-Hant"), .leftToRight)
        XCTAssertEqual(AppLayoutDirection.direction(forLanguage: ""), .leftToRight)
    }

    /// The chips in a settings group wrap from the leading edge; Arabic starts
    /// each line at the right and wraps to a second line above.
    func testTheFlowLayoutFillsFromTheRightInArabic() {
        let rtl = render(flowRow(direction: .rightToLeft), size: CGSize(width: 100, height: 60))
        // Both red chips are the first line: one at the right edge, one 8 pt in.
        let firstLine = inkBounds(rtl) { $0.redComponent > 0.9 && $0.greenComponent < 0.2 }
        XCTAssertGreaterThanOrEqual(firstLine.maxX, 89, "The first chip must touch the right edge")
        XCTAssertGreaterThanOrEqual(firstLine.minX, 7)

        let wrapped = inkBounds(rtl) { $0.blueComponent > 0.9 && $0.redComponent < 0.2 }
        XCTAssertGreaterThanOrEqual(wrapped.minX, 54, "The second line must start at the right edge too")
        XCTAssertGreaterThan(wrapped.minY, 19, "The third chip is on a second line")
    }

    /// Only icons that point along the reading order turn. A folder does not.
    func testNonDirectionalIconsStayPut() {
        let ltr = render(folderIcon, size: CGSize(width: 16, height: 16), direction: .leftToRight)
        let rtl = render(folderIcon, size: CGSize(width: 16, height: 16), direction: .rightToLeft)
        XCTAssertEqual(inkCenterX(rtl), inkCenterX(ltr), accuracy: 0.5)
    }

    /// The settings slider's thumb starts at the right in Arabic; dragging
    /// toward the left raises the value.
    func testTheSliderThumbStartsOnTheRightInArabic() {
        let rtl = render(slider, size: CGSize(width: 200, height: 22), direction: .rightToLeft)
        let ltr = render(slider, size: CGSize(width: 200, height: 22), direction: .leftToRight)
        // The thumb is near-white and the accent fill is bright; the track is dim.
        let bright: (NSColor) -> Bool = { ($0.redComponent + $0.greenComponent + $0.blueComponent) / 3 > 0.45 }
        XCTAssertGreaterThan(inkBounds(rtl, matching: bright).midX, 119)
        XCTAssertLessThan(inkBounds(ltr, matching: bright).midX, 81)
    }

    // MARK: - Fixtures

    /// A colour of its own, not SwiftUI's system red: the matchers below look
    /// for a red with no green, and `.red` is (1.0, 0.23, 0.19) on macOS.
    private static let pigment = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1)

    /// Rails are 228 pt; the probe keeps the same proportions in a small frame.
    private var twoPaneShell: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Self.pigment).frame(width: 40)
            Rectangle().fill(Color.green)
        }
        .frame(width: 240, height: 40)
        .background(Color.black)
    }

    private var chevron: some View {
        SiftIcon.chevronRight.image(16)
            .foregroundStyle(Color.white)
            .frame(width: 16, height: 16)
            .background(Color.black)
    }

    private var meter: some View {
        SiftMeterBar(fraction: 0.25, fill: Self.pigment)
            .frame(width: 200)
            .background(Color.black)
    }

    /// A quarter-full slider: thumb near the leading edge.
    private var slider: some View {
        SiftSlider(value: .constant(0.25), range: 0...1)
            .frame(width: 200, height: 22)
            .background(Color.black)
    }

    private var folderIcon: some View {
        SiftIcon.folder.image(16)
            .foregroundStyle(Color.white)
            .frame(width: 16, height: 16)
            .background(Color.black)
    }

    /// Three 40 pt chips in a 100 pt column: two on the first line, one below.
    private func flowRow(direction: LayoutDirection) -> some View {
        SiftFlowLayout(layoutDirection: direction) {
            Self.pigment.frame(width: 40, height: 20)
            Self.pigment.frame(width: 40, height: 20)
            Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1).frame(width: 40, height: 20)
        }
        .frame(width: 100, height: 60)
        .background(Color.black)
    }

    private func whereRow(direction: LayoutDirection) -> some View {
        WhereRowLayout.Row(spacing: 10, layoutDirection: direction) {
            Self.pigment.frame(width: 32, height: 32)
            Color.green.frame(width: 100, height: 20)
            Color.blue.frame(width: 56, height: 6)
            Color.yellow.frame(width: 72, height: 20)
            Color.purple.frame(width: 16, height: 16)
        }
        .frame(width: 300, height: 40)
        .background(Color.black)
    }

    // MARK: - Rendering

    private func render<V: View>(_ view: V, size: CGSize, direction: LayoutDirection? = nil) -> NSBitmapImageRep {
        var content = AnyView(view.frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        if let direction { content = AnyView(content.environment(\.layoutDirection, direction)) }
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        // SwiftUI settles on its first layout in a run-loop turn; without this
        // a fresh hosting view can rasterize blank.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not rasterize the view")
            return NSBitmapImageRep()
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func inkBounds(_ rep: NSBitmapImageRep, matching: (NSColor) -> Bool) -> CGRect {
        let scale = CGFloat(rep.pixelsWide) / max(1, rep.size.width)
        var minX = CGFloat.greatestFiniteMagnitude, maxX: CGFloat = 0
        var minY = CGFloat.greatestFiniteMagnitude, maxY: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), matching(color) else { continue }
                minX = min(minX, CGFloat(x) / scale)
                maxX = max(maxX, CGFloat(x) / scale)
                minY = min(minY, CGFloat(y) / scale)
                maxY = max(maxY, CGFloat(y) / scale)
            }
        }
        guard minX < .greatestFiniteMagnitude else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func inkCenterX(_ rep: NSBitmapImageRep) -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / max(1, rep.size.width)
        var sum: CGFloat = 0
        var count: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard color.redComponent + color.greenComponent + color.blueComponent > 0.5 else { continue }
                sum += CGFloat(x) / scale
                count += 1
            }
        }
        return count > 0 ? sum / count : 0
    }
}
