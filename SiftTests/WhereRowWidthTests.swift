import SwiftUI
import XCTest
@testable import Sift

/// The Overview rows must keep the label readable: the meter is the column that
/// gives way, never the name of the category. These tests render the real row
/// and measure how many points of the title the layout actually draws.
@MainActor
final class WhereRowWidthTests: XCTestCase {
    private let rowHeight: CGFloat = 48
    /// Row padding 10 + icon tile 32 + the 14 pt gap after the tile.
    private let labelX: CGFloat = 56

    func testLabelIsDrawnInFullAtTheMinimumWindowWidth() {
        let rowWidth = WhereRowLayout.rowWidth(atWindowWidth: 1080)
        for label in ["Developer caches", "Large & old files"] {
            let ideal = idealTitleWidth(label)
            let drawn = drawnTitleWidth(label: label, rowWidth: rowWidth, limit: ideal + 40)
            XCTAssertGreaterThanOrEqual(
                drawn,
                ideal - 1,
                "“\(label)” is clipped to \(Int(drawn)) pt of its \(Int(ideal)) pt in a \(Int(rowWidth)) pt row"
            )
        }
    }

    // MARK: - Rendering

    private func idealTitleWidth(_ label: String) -> CGFloat {
        let font = SiftFonts.nsFont(SiftFonts.ui, size: 13, weight: 500)
            ?? NSFont.systemFont(ofSize: 13, weight: .medium)
        let text = NSAttributedString(string: label, attributes: [.font: font])
        return ceil(text.size().width)
    }

    /// Rightmost point of near-white (title) pixels inside the label column,
    /// relative to the column's left edge.
    private func drawnTitleWidth(label: String, rowWidth: CGFloat, limit: CGFloat) -> CGFloat {
        let item = SiftRail.Item(
            section: .cleaning(.xcodeJunk),
            label: LocalizedStringKey(label),
            icon: .codeXml
        )
        let row = WhereItSitsCard.Row(
            item: item,
            size: 2_000_000_000,
            count: 12,
            measured: true
        )
        let content = WhereRow(row: row, fraction: 0.55, isLargest: false) {}
            .frame(width: rowWidth, height: rowHeight)
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: AnyView(content))
        host.frame = NSRect(x: 0, y: 0, width: rowWidth, height: rowHeight)
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not rasterize the row")
            return 0
        }
        host.cacheDisplay(in: host.bounds, to: rep)

        let scale = CGFloat(rep.pixelsWide) / max(1, rowWidth)
        var rightmost: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let px = CGFloat(x) / scale
                guard px >= labelX, px <= labelX + limit else { continue }
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let red = color.redComponent * 255
                let green = color.greenComponent * 255
                let blue = color.blueComponent * 255
                // Title text is near-white; the subtitle is muted and the meter
                // and chevron are tinted, so only the title hits all three.
                guard red > 210, green > 210, blue > 200 else { continue }
                rightmost = max(rightmost, px - labelX)
            }
        }
        return rightmost
    }
}
