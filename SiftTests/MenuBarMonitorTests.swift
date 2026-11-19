import AppKit
import XCTest
@testable import Sift

final class MenuBarMonitorTests: XCTestCase {
    /// Decimal file sizes, the way the dashboard, the rail and the CLI show
    /// them, so the menu bar cannot quote a different total for the same disk.
    func testDiskDetailUsesFileSizes() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB, .usePB]

        let used: Int64 = 199_756_000_000
        let total: Int64 = 245_107_908_608
        let expected = formatter.string(fromByteCount: used)
            + " / "
            + formatter.string(fromByteCount: total)

        XCTAssertEqual(MenuBarMonitorView.diskDetail(used: used, total: total), expected)
    }

    /// A disk smaller than one gigabyte must not fall back to "Zero KB", and a
    /// zero reading must still read as a size rather than a blank.
    func testDiskDetailKeepsSmallAndEmptyReadingsReadable() {
        XCTAssertEqual(MenuBarMonitorView.diskDetail(used: 0, total: 0), "0 KB / 0 KB")
        XCTAssertEqual(
            MenuBarMonitorView.diskDetail(used: 512_000, total: 900_000),
            "\(SiftFormat.bytes(512_000)) / \(SiftFormat.bytes(900_000))"
        )
    }

    /// RAM stays binary, so the popover agrees with the Performance screen
    /// (16 GB of memory, not 17.2 GB).
    func testMemoryDetailStaysBinary() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        let used: Int64 = 11_900_000_000
        let total: Int64 = 17_179_869_184
        let expected = formatter.string(fromByteCount: used)
            + " / "
            + formatter.string(fromByteCount: total)

        XCTAssertEqual(MenuBarMonitorView.memoryDetail(used: used, total: total), expected)
        XCTAssertEqual(MenuBarMonitorView.memoryDetail(used: total, total: total).hasSuffix("16 GB"), true)
    }
}
