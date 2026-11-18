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

    /// The label gets its text width first; the meter takes the rest, gives
    /// way down to its minimum, and only then does the label lose points.
    func testLabelWinsTheWidthBeforeTheMeterShrinks() {
        let narrow = WhereRowLayout.rowWidth(atWindowWidth: 1080) - WhereRowLayout.fixedChrome
        let ideal: CGFloat = 106
        XCTAssertGreaterThanOrEqual(
            WhereRowLayout.labelWidth(space: narrow, labelIdealWidth: ideal),
            ideal,
            "A 1080 pt window leaves room for the whole category name"
        )
        XCTAssertGreaterThanOrEqual(
            WhereRowLayout.meterWidth(space: narrow, labelIdealWidth: ideal),
            WhereRowLayout.meterMinWidth
        )

        let cramped: CGFloat = 150
        XCTAssertEqual(WhereRowLayout.meterWidth(space: cramped, labelIdealWidth: ideal), WhereRowLayout.meterMinWidth)
        XCTAssertEqual(WhereRowLayout.labelWidth(space: cramped, labelIdealWidth: ideal), cramped - WhereRowLayout.meterMinWidth)
    }

    func testRowWidthMatchesTheOverviewLayout() {
        XCTAssertEqual(WhereRowLayout.rowWidth(atWindowWidth: 1080), 372)
        XCTAssertEqual(
            WhereRowLayout.rowWidth(atWindowWidth: 1_600),
            892
        )
    }

    func testWideRowKeepsTheMeterAtItsIdealWidth() {
        let wide = WhereRowLayout.rowWidth(atWindowWidth: 1_600) - WhereRowLayout.fixedChrome
        XCTAssertEqual(
            WhereRowLayout.meterWidth(space: wide, labelIdealWidth: 106),
            WhereRowLayout.meterIdealWidth
        )
    }
}
