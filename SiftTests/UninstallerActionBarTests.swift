import AppKit
import SwiftUI
import XCTest

@testable import Sift

/// The Uninstaller footer has to show what is about to be removed. It used to
/// lose that fight to the buttons next to it: at the 1080 pt window the
/// summary collapsed to a few points and the user saw one clipped glyph
/// between "Dry run" and "Review removal". The summary now has a line of its
/// own above the buttons, and these tests render the real footer to prove it
/// is drawn in full.
@MainActor
final class UninstallerActionBarTests: XCTestCase {
    /// The longest summary each shipped language can produce for 25 files.
    private let summaries = [
        "25 items, 1.12 GB",
        "25 Elemente, 1,12 GB",
        "25 élément(s), 1,12 Go",
        "25 элементов, 1,12 ГБ",
        "٢٥ عنصرًا، ١٫١٢ غيغابايت",
        "25 項目、1.12 GB",
    ]

    /// The card is padded 24 pt on both sides.
    private let barWidth: CGFloat = 1080 - 2 * 24
    private let barHeight: CGFloat = 60

    func testTheSelectionSummaryIsDrawnInFullAtTheMinimumWindowWidth() {
        for summary in summaries {
            let full = drawnSummaryWidth(summary, width: 1_600 - 2 * 24)
            let drawn = drawnSummaryWidth(summary, width: barWidth)
            XCTAssertGreaterThan(full, 0, "“\(summary)” drew nothing even in a wide window")
            XCTAssertEqual(
                drawn, full, accuracy: 1,
                "“\(summary)” drew \(Int(drawn)) pt of the \(Int(full)) pt it draws in a wide window")
        }
    }

    func testTheSelectionSummarySitsAtTheTrailingEdgeOfItsLine() {
        for summary in summaries {
            let ink = drawnSummaryInk(summary, width: barWidth)
            XCTAssertGreaterThanOrEqual(ink.maxX, barWidth - 30, "“\(summary)” is not right-aligned")
        }
    }

    // MARK: - Rendering

    private func bar(summary: String) -> some View {
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

    private func bitmap(summary: String, width: CGFloat) -> NSBitmapImageRep {
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

    private func drawnSummaryInk(_ summary: String, width: CGFloat) -> Ink {
        let rep = bitmap(summary: summary, width: width)
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

    private func drawnSummaryWidth(_ summary: String, width: CGFloat) -> CGFloat {
        drawnSummaryInk(summary, width: width).width
    }
}
