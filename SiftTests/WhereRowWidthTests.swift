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

    // MARK: - Edge cases

    func testLongestLocalizedLabelNeverStarvesTheMeter() throws {
        let rowWidth = WhereRowLayout.rowWidth(atWindowWidth: 1080)
        let labels = try widestCleanupLabelPerLanguage()
        XCTAssertGreaterThanOrEqual(labels.count, 13, "Every shipped language must be covered")

        for (language, label) in labels.sorted(by: { $0.key < $1.key }) {
            let full = drawnTitleWidth(label: label, rowWidth: WhereRowLayout.rowWidth(atWindowWidth: 1_600), limit: 400)
            let drawn = drawnTitleWidth(label: label, rowWidth: rowWidth, limit: 400)
            let meter = drawnMeterWidth(label: label, rowWidth: rowWidth)
            XCTAssertGreaterThanOrEqual(
                meter,
                WhereRowLayout.meterMinWidth - 1,
                "\(language) “\(label)” squeezed the meter to \(Int(meter)) pt"
            )
            XCTAssertGreaterThanOrEqual(
                drawn,
                full - 1,
                "\(language) “\(label)” drew \(Int(drawn)) pt of the \(Int(full)) pt it draws in a wide row"
            )
        }
    }

    func testWideWindowKeepsTheMeterAtItsIdealWidth() {
        let rowWidth = WhereRowLayout.rowWidth(atWindowWidth: 1_600)
        let label = "Large & old files"

        let meter = drawnMeterWidth(label: label, rowWidth: rowWidth)
        let ideal = idealTitleWidth(label)
        let drawn = drawnTitleWidth(label: label, rowWidth: rowWidth, limit: ideal + 40)

        XCTAssertEqual(meter, WhereRowLayout.meterIdealWidth, accuracy: 1, "The meter stops growing at its ideal width")
        XCTAssertGreaterThanOrEqual(drawn, ideal - 1)
    }

    // MARK: - Languages

    /// The widest of the seven cleanup labels in each shipped language.
    private func widestCleanupLabelPerLanguage() throws -> [String: String] {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = sourceRoot.appendingPathComponent("Sift")
        let keys: Set<String> = [
            "System junk", "AI tools", "Developer caches", "Project junk",
            "Installers", "Large & old files", "Mail files", "Trash",
        ]
        var widest: [String: String] = [:]
        for language in AppLanguage.allCases.map(\.rawValue) where language != "system" {
            let file = appSource
                .appendingPathComponent("\(language).lproj")
                .appendingPathComponent("Localizable.strings")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (key, value) in parseStrings(text) where keys.contains(key) {
                if let current = widest[language], idealTitleWidth(current) >= idealTitleWidth(value) {
                    continue
                }
                widest[language] = value
            }
        }
        return widest
    }

    private func parseStrings(_ text: String) -> [String: String] {
        var pairs: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\""),
                  let firstQuote = trimmed.firstIndex(of: "\""),
                  let secondQuote = trimmed[trimmed.index(after: firstQuote)...].firstIndex(of: "\""),
                  let equals = trimmed[trimmed.index(after: secondQuote)...].firstIndex(of: "="),
                  let thirdQuote = trimmed[trimmed.index(after: equals)...].firstIndex(of: "\""),
                  let fourthQuote = trimmed[trimmed.index(after: thirdQuote)...].firstIndex(of: "\"")
            else { continue }
            let key = String(trimmed[trimmed.index(after: firstQuote)..<secondQuote])
            let value = String(trimmed[trimmed.index(after: thirdQuote)..<fourthQuote])
            pairs[key] = value
        }
        return pairs
    }

    // MARK: - Rendering

    /// Width of the meter as laid out: its right edge sits a fixed distance
    /// from the row's trailing edge (size column, gaps, chevron, padding), so
    /// walking left over the track's pixels until the gap gives its width.
    private func drawnMeterWidth(label: String, rowWidth: CGFloat) -> CGFloat {
        let bitmap = renderRow(label: label, rowWidth: rowWidth)
        let scale = CGFloat(bitmap.rep.pixelsWide) / max(1, rowWidth)
        let padding: CGFloat = 10, chevron: CGFloat = 16, gap: CGFloat = 14, sizeColumn: CGFloat = 72
        let trailingChrome = padding + chevron + gap + sizeColumn + gap
        let rightEdge = rowWidth - trailingChrome
        var widths: [CGFloat] = []
        for y in stride(from: 0, to: bitmap.rep.pixelsHigh, by: 1) {
            let centerY = CGFloat(y) / scale
            guard centerY >= 21, centerY <= 27 else { continue }
            var left = rightEdge
            var run: CGFloat = 0
            while left > 0 {
                let x = Int((left - 0.5) * scale)
                guard x >= 0, x < bitmap.rep.pixelsWide,
                      let color = bitmap.rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                else { break }
                let luma = (color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255
                guard luma > 12, luma < 120 else { break }
                run += 1 / scale
                left -= 1 / scale
            }
            widths.append(run)
        }
        return widths.max() ?? 0
    }

    private func renderRow(label: String, rowWidth: CGFloat) -> (rep: NSBitmapImageRep, host: NSHostingView<AnyView>) {
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
        host.displayIfNeeded()
        // SwiftUI settles on its first layout in a run-loop turn; without this
        // a fresh hosting view can rasterize blank.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            XCTFail("Could not rasterize the row")
            return (NSBitmapImageRep(), host)
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        return (rep, host)
    }

    private func idealTitleWidth(_ label: String) -> CGFloat {
        let font = SiftFonts.nsFont(SiftFonts.ui, size: 13, weight: 500)
            ?? NSFont.systemFont(ofSize: 13, weight: .medium)
        let text = NSAttributedString(string: label, attributes: [.font: font])
        return ceil(text.size().width)
    }

    /// Rightmost point of near-white (title) pixels inside the label column,
    /// relative to the column's left edge.
    private func drawnTitleWidth(label: String, rowWidth: CGFloat, limit: CGFloat) -> CGFloat {
        let (rep, _) = renderRow(label: label, rowWidth: rowWidth)
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
                guard red > 170, green > 170, blue > 160 else { continue }
                rightmost = max(rightmost, px - labelX)
            }
        }
        return rightmost
    }
}
