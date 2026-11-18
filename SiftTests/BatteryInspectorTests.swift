import XCTest
@testable import Sift

final class BatteryInspectorTests: XCTestCase {
    func testPowerSourceReadsACStateAndMinutesToFullWhileCharging() {
        let reading = BatteryInspector.powerSourceReading(from: [
            "Power Source State": "AC Power",
            "Is Charging": true,
            "Time to Full Charge": 42,
        ])
        XCTAssertEqual(reading.isOnACPower, true)
        XCTAssertEqual(reading.minutesToFull, 42)
    }

    func testPowerSourceTreatsMinusOneAsStillCalculating() {
        let reading = BatteryInspector.powerSourceReading(from: [
            "Power Source State": "AC Power",
            "Is Charging": true,
            "Time to Full Charge": -1,
        ])
        XCTAssertNil(reading.minutesToFull)
    }

    func testPowerSourceHasNoTimeToFullOnBatteryPower() {
        let reading = BatteryInspector.powerSourceReading(from: [
            "Power Source State": "Battery Power",
            "Is Charging": false,
            "Time to Full Charge": 0,
        ])
        XCTAssertEqual(reading.isOnACPower, false)
        XCTAssertNil(reading.minutesToFull, "Not charging, so there is no time to full")
    }

    func testPowerSourceLeavesMissingKeysUnknown() {
        let reading = BatteryInspector.powerSourceReading(from: [:])
        XCTAssertNil(reading.isOnACPower)
        XCTAssertNil(reading.minutesToFull)
    }
}
