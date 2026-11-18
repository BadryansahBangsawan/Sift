import XCTest
@testable import Sift

final class DashboardLayoutTests: XCTestCase {
    /// The Overview card is ~292 pt wide at the 1080 pt minimum window width and
    /// the meter is the only flexible column, so it collapsed to a dot. It keeps
    /// its minimum width and the label column truncates instead.
    func testWhereRowMeterKeepsAMinimumWidth() {
        XCTAssertGreaterThanOrEqual(WhereRowLayout.meterMinWidth, 56)
        XCTAssertGreaterThanOrEqual(WhereRowLayout.meterIdealWidth, WhereRowLayout.meterMinWidth)
    }
}
