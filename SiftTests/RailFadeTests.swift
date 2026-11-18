import XCTest
@testable import Sift

final class RailFadeTests: XCTestCase {
    /// At short window heights the rail list scrolls without a scroller, so the
    /// last rows are simply cut off. A fade on the edge that hides content
    /// reads as "there is more".
    func testListThatOverflowsFadesItsBottomEdgeAtRest() {
        let fades = RailFadeRule.fades(offset: 0, contentHeight: 920, viewport: 600)
        XCTAssertFalse(fades.top)
        XCTAssertTrue(fades.bottom)
    }

    func testAScrolledListFadesBothEdges() {
        let fades = RailFadeRule.fades(offset: 120, contentHeight: 920, viewport: 600)
        XCTAssertTrue(fades.top)
        XCTAssertTrue(fades.bottom)
    }

    func testTheEndOfTheListDropsTheBottomFade() {
        let fades = RailFadeRule.fades(offset: 320, contentHeight: 920, viewport: 600)
        XCTAssertTrue(fades.top)
        XCTAssertFalse(fades.bottom)
    }

    func testAListThatFitsShowsNoFade() {
        let fades = RailFadeRule.fades(offset: 0, contentHeight: 560, viewport: 600)
        XCTAssertFalse(fades.top)
        XCTAssertFalse(fades.bottom)
    }

    /// Sub-point overscroll from the rubber-band effect must not flip the fades.
    func testRubberBandOverscrollKeepsTheEndState() {
        let top = RailFadeRule.fades(offset: -3, contentHeight: 920, viewport: 600)
        XCTAssertFalse(top.top)
        XCTAssertTrue(top.bottom)

        let bottom = RailFadeRule.fades(offset: 325, contentHeight: 920, viewport: 600)
        XCTAssertTrue(bottom.top)
        XCTAssertFalse(bottom.bottom)
    }
}
