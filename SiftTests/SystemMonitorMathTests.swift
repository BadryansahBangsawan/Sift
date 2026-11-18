import XCTest
@testable import Sift

final class SystemMonitorMathTests: XCTestCase {
    func testCPULoadSplitsTheTickDeltaIntoUserSystemAndIdle() throws {
        let previous = SystemMonitor.CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        // +30 user, +20 nice, +10 system, +40 idle = 100 ticks.
        let current = SystemMonitor.CPUTicks(user: 130, system: 60, idle: 840, nice: 70)

        let load = try XCTUnwrap(SystemMonitor.cpuLoad(from: previous, to: current))

        XCTAssertEqual(load.user, 0.5, accuracy: 1e-9, "Nice time counts as user time")
        XCTAssertEqual(load.system, 0.1, accuracy: 1e-9)
        XCTAssertEqual(load.idle, 0.4, accuracy: 1e-9)
        XCTAssertEqual(load.total, 0.6, accuracy: 1e-9)
    }

    func testCPULoadNeedsABaselineAndForwardProgress() {
        let zero = SystemMonitor.CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        let sample = SystemMonitor.CPUTicks(user: 10, system: 10, idle: 10, nice: 0)
        XCTAssertNil(SystemMonitor.cpuLoad(from: zero, to: sample), "First sample has no baseline")
        XCTAssertNil(SystemMonitor.cpuLoad(from: sample, to: sample), "No ticks elapsed")
    }

    func testCPUHistoryKeepsTheNewestThirtySamplesOldestFirst() {
        var history: [Double] = []
        for value in 1...32 {
            history = SystemMonitor.appendingHistory(Double(value), to: history)
        }
        XCTAssertEqual(history.count, 30)
        XCTAssertEqual(history.first, 3)
        XCTAssertEqual(history.last, 32)
    }

    func testMemoryBreakdownMultipliesPageCountsByPageSize() {
        let breakdown = SystemMonitor.memoryBreakdown(
            wireCount: 10,
            activeCount: 20,
            compressorPageCount: 5,
            freeCount: 7,
            pageSize: 16_384
        )
        XCTAssertEqual(breakdown.wired, 163_840)
        XCTAssertEqual(breakdown.active, 327_680)
        XCTAssertEqual(breakdown.compressed, 81_920)
        XCTAssertEqual(breakdown.free, 114_688)
        XCTAssertEqual(breakdown.used, 573_440, "Used stays active + wired + compressed")
    }
}
