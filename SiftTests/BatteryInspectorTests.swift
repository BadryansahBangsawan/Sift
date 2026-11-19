import XCTest
@testable import Sift

final class BatteryInspectorTests: XCTestCase {
    func testPmsetChargingStatesFollowTheReportedState() {
        func output(_ state: String) -> String {
            """
            Now drawing from 'AC Power'
             -InternalBattery-0 (id=466'\t'') 72%; \(state); 1:12 remaining present: true
            """
        }

        XCTAssertEqual(BatteryInspector.chargingState(fromPmset: output("charging")), true)
        XCTAssertEqual(BatteryInspector.chargingState(fromPmset: output("finishing charge")), true)
        XCTAssertEqual(BatteryInspector.chargingState(fromPmset: output("charged")), true)
        XCTAssertEqual(BatteryInspector.chargingState(fromPmset: output("discharging")), false)
        XCTAssertEqual(
            BatteryInspector.chargingState(fromPmset: output("AC attached; not charging")),
            false,
            "Optimised charging holds at a percentage; 'not charging' must not read as charging"
        )
        XCTAssertNil(BatteryInspector.chargingState(fromPmset: output("AC attached")))
        XCTAssertNil(BatteryInspector.chargingState(fromPmset: ""))
        XCTAssertEqual(
            BatteryInspector.chargingState(fromPmset: "Now drawing from 'AC Power'\n -InternalBattery-0 100%; CHARGED; 0:00 remaining"),
            true,
            "pmset capitalisation must not change the answer"
        )
        XCTAssertEqual(
            BatteryInspector.chargingState(fromPmset: "Now drawing from 'Battery Power'\n -InternalBattery-0 42%; DISCHARGING; 3:10 remaining"),
            false
        )
        XCTAssertNil(BatteryInspector.chargingState(fromPmset: "Now drawing from 'AC Power'"))
        XCTAssertNil(
            BatteryInspector.chargingState(fromPmset: "-InternalBattery-0 42%; 3:10 remaining present: true"),
            "A line without a state word leaves the state unknown rather than guessing"
        )
    }

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
