import XCTest
@testable import Sift

/// The selection bar carries the selected count in a 28 pt circle. From four
/// digits on ("1000") the text no longer fits, so it wrapped and the pill grew
/// into a tall oval. Numbers stay on one line in a capsule that widens.
final class SelectionBadgeTests: XCTestCase {
    func testShortCountsKeepTheCircle() {
        XCTAssertEqual(SelectionBadgeRule.horizontalPadding(for: 0), 0)
        XCTAssertEqual(SelectionBadgeRule.horizontalPadding(for: 9), 0)
        XCTAssertEqual(SelectionBadgeRule.horizontalPadding(for: 99), 0)
    }

    func testFourAndFiveDigitCountsGetRoom() {
        XCTAssertGreaterThan(SelectionBadgeRule.horizontalPadding(for: 100), 0)
        XCTAssertGreaterThanOrEqual(SelectionBadgeRule.horizontalPadding(for: 1_000), 8)
        XCTAssertGreaterThanOrEqual(SelectionBadgeRule.horizontalPadding(for: 12_345), 8)
    }

    func testTheBadgeKeepsAOneLineHeight() {
        XCTAssertEqual(SelectionBadgeRule.minimumSize, 28)
        XCTAssertGreaterThan(SelectionBadgeRule.minimumSize, 0)
    }

    /// The two-digit case still fills the circle exactly, so the badge looks
    /// unchanged until it has to grow.
    func testTwoDigitsFillTheCircle() {
        XCTAssertEqual(SelectionBadgeRule.horizontalPadding(for: 99), 0)
        XCTAssertLessThan(SelectionBadgeRule.horizontalPadding(for: 100), SelectionBadgeRule.minimumSize)
    }

    /// The widening stops after the first step: five digits use the same
    /// padding as four and the text scales instead of stretching the bar.
    func testWideningIsOneStep() {
        XCTAssertEqual(
            SelectionBadgeRule.horizontalPadding(for: 9_999),
            SelectionBadgeRule.horizontalPadding(for: 1_000)
        )
    }
}
