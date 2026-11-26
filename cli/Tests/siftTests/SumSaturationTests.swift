import XCTest
@testable import sift

final class SumSaturationTests: XCTestCase {
    func testSaturatedSumClampsAtMaxInsteadOfTrapping() {
        XCTAssertEqual(Int64.max.saturatedSum(10), .max)
        XCTAssertEqual(Int64(5).saturatedSum(7), 12)
    }
}
