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

    /// Icon tile 32 + three 14 pt gaps + row padding 20 + size column 72 +
    /// chevron 16 + the meter minimum must still leave the label something to
    /// show inside the ~292 pt card at the 1080 pt window minimum.
    func testMinimumCardWidthLeavesRoomForTheLabel() {
        let fixed = 32 + 14 * 3 + 20 + 72 + 16 + WhereRowLayout.meterMinWidth
        XCTAssertLessThan(fixed, 292)
        XCTAssertGreaterThanOrEqual(292 - fixed, 40)
    }

    /// The meter settles at its ideal width when the card is spacious.
    func testMeterDoesNotGrowPastItsIdealWidth() {
        XCTAssertLessThanOrEqual(WhereRowLayout.meterIdealWidth, 120)
    }
}
