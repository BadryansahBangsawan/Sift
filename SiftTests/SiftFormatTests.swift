import AppKit
import XCTest

@testable import Sift

/// One byte formatter for the whole app. Every size the UI or the CLI prints
/// must come from `SiftFormat.bytes`, so an empty size reads "0 KB" and never
/// the formatter's spelled-out "Zero KB".
final class SiftFormatTests: XCTestCase {
    private let sizes: [Int64] = [0, 1, 999, 1_234_567, 64_000_000_000]

    func testEverySizeLabelUsesTheOneFormatter() {
        for size in sizes {
            let expected = SiftFormat.bytes(size)
            let item = CleanableItem(
                name: "x", path: "/tmp/x", size: size, category: .systemJunk,
                isSelected: false, lastModified: nil)
            XCTAssertEqual(item.formattedSize, expected, "item size \(size)")

            let result = CategoryResult(category: .systemJunk, items: [item], totalSize: size)
            XCTAssertEqual(result.formattedSize, expected, "category size \(size)")

            let group = CategoryGroupResult(categories: [.systemJunk], results: [.systemJunk: result])
            XCTAssertEqual(group.formattedSize, expected, "group size \(size)")

            let disk = DiskInfo(totalSpace: size, freeSpace: size, usedSpace: size, purgeableSpace: size)
            XCTAssertEqual(disk.formattedTotal, expected, "disk total \(size)")
            XCTAssertEqual(disk.formattedFree, expected, "disk free \(size)")
            XCTAssertEqual(disk.formattedUsed, expected, "disk used \(size)")
            XCTAssertEqual(disk.formattedPurgeable, expected, "disk purgeable \(size)")

            let app = InstalledApp(
                id: UUID(), appName: "A", bundleIdentifier: "b",
                path: URL(fileURLWithPath: "/Applications/A.app"),
                icon: NSImage(), size: size)
            XCTAssertEqual(app.formattedSize, expected, "app size \(size)")
        }
    }

    func testAnEmptySizeIsNeverSpeltOut() {
        XCTAssertEqual(SiftFormat.bytes(0), "0 KB")
        let item = CleanableItem(
            name: "empty", path: "/tmp/empty", size: 0, category: .systemJunk,
            isSelected: false, lastModified: nil)
        let result = CategoryResult(category: .systemJunk, items: [], totalSize: 0)
        let app = InstalledApp(
            id: UUID(), appName: "A", bundleIdentifier: "b",
            path: URL(fileURLWithPath: "/Applications/A.app"), icon: NSImage(), size: 0)
        for (label, text) in [
            ("item", item.formattedSize),
            ("category", result.formattedSize),
            ("app", app.formattedSize),
            ("disk", DiskInfo().formattedFree),
        ] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("zero"), "\(label) spells out zero: \(text)")
        }
    }
}
