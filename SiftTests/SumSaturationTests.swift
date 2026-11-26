import XCTest
@testable import Sift

@MainActor
final class SumSaturationTests: XCTestCase {
    func testDisplayedJunkTotalSaturatesInsteadOfTrapping() {
        let state = AppState(performStartupTasks: false)
        state.categoryResults[.systemJunk] = CategoryResult(
            category: .systemJunk,
            items: [],
            totalSize: .max
        )
        state.categoryResults[.userCache] = CategoryResult(
            category: .userCache,
            items: [],
            totalSize: 10
        )

        state.recomputeTotalJunkSize()

        XCTAssertEqual(state.totalJunkSize, .max, "An oversized scan must saturate, not crash the app")
    }
}
