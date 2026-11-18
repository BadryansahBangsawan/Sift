import XCTest
@testable import Sift

final class DashboardChipSizeTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureHome = fileManager.temporaryDirectory
            .appendingPathComponent("DashboardChipSizeTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureHome { try? fileManager.removeItem(at: fixtureHome) }
        try super.tearDownWithError()
    }

    func testContainersSizeTotalsEveryContainer() async throws {
        let containers = fixtureHome.appendingPathComponent("Library/Containers", isDirectory: true)
        let first = containers.appendingPathComponent("com.example.one/Data/Library", isDirectory: true)
        let second = containers.appendingPathComponent("com.example.two/Data", isDirectory: true)
        try fileManager.createDirectory(at: first, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: second, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 16_384).write(to: first.appendingPathComponent("db.sqlite"))
        try Data(repeating: 2, count: 8_192).write(to: second.appendingPathComponent(".hidden"))

        let size = await ScanEngine(homeDirectory: fixtureHome).containersSize()

        XCTAssertGreaterThanOrEqual(size, 16_384 + 8_192)
        XCTAssertLessThan(size, 16_384 + 8_192 + 64 * 1024)
    }

    func testMissingContainersFolderMeasuresZero() async {
        let size = await ScanEngine(homeDirectory: fixtureHome).containersSize()
        XCTAssertEqual(size, 0)
    }
}
