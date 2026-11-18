import XCTest
@testable import Sift

final class PerformanceBatteryTests: XCTestCase {
    /// The card already shows the health percentage above this caption, so the
    /// caption may only claim a service threshold when the number is below it.
    func testHealthCaptionStaysSilentAboveEighty() {
        let status = BatteryStatus(
            isInstalled: true,
            maxCapacityMAh: 4024,
            designCapacityMAh: 4629,
            healthPercent: 87
        )
        XCTAssertEqual(PerformanceView.batteryHealthDetail(status), "4024 of 4629 mAh")
    }

    func testHealthCaptionNamesTheThresholdBelowEighty() {
        let status = BatteryStatus(
            isInstalled: true,
            maxCapacityMAh: 3200,
            designCapacityMAh: 4629,
            healthPercent: 71
        )
        XCTAssertEqual(PerformanceView.batteryHealthDetail(status), "3200 of 4629 mAh, service below 80%")
    }
}
