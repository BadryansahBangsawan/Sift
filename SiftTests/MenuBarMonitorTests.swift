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
}
