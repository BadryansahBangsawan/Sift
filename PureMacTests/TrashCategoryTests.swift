import XCTest
@testable import PureMac

final class TrashCategoryTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureHome = fileManager.temporaryDirectory
            .appendingPathComponent("TrashCategoryTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureHome { try? fileManager.removeItem(at: fixtureHome) }
        try super.tearDownWithError()
    }

    func testTrashIsMeasuredBySmartScanButNeverScheduledOrBulkCleaned() {
        XCTAssertTrue(CleaningCategory.smartScanCategories.contains(.trash))
        XCTAssertFalse(CleaningCategory.scannable.contains(.trash))
        XCTAssertFalse(ScheduleConfig().categoriesToScan.contains(.trash))
        XCTAssertEqual(
            CleaningCategory.smartScanCategories.filter { $0 != .trash },
            CleaningCategory.scannable
        )
    }

    func testTrashMetadataMatchesOtherCategories() {
        XCTAssertEqual(CleaningCategory.trash.rawValue, "Trash")
        XCTAssertEqual(CleaningCategory.trash.icon, "trash.fill")
        XCTAssertFalse(CleaningCategory.trash.description.isEmpty)
    }

    func testScanMeasuresTopLevelTrashEntriesWithoutSelectingThem() async throws {
        let trash = fixtureHome.appendingPathComponent(".Trash", isDirectory: true)
        let folder = trash.appendingPathComponent("Old Project", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: folder.appendingPathComponent("a.bin"))
        try Data(repeating: 2, count: 4_096).write(to: folder.appendingPathComponent("b.bin"))
        try Data(repeating: 3, count: 100).write(to: trash.appendingPathComponent("tiny.txt"))
        try Data(repeating: 4, count: 10).write(to: trash.appendingPathComponent(".DS_Store"))

        let result = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.trash)

        XCTAssertEqual(result.category, .trash)
        XCTAssertEqual(Set(result.items.map(\.name)), ["Old Project", "tiny.txt"])
        XCTAssertTrue(result.items.allSatisfy { !$0.isSelected })
        XCTAssertTrue(result.items.allSatisfy { $0.category == .trash })
        XCTAssertGreaterThanOrEqual(result.totalSize, 8_192 + 4_096 + 100)
        XCTAssertEqual(result.totalSize, result.items.reduce(0) { $0 + $1.size })
    }

    func testUnreadableOrMissingTrashScansAsEmpty() async {
        let result = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.trash)

        XCTAssertEqual(result.category, .trash)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.totalSize, 0)
    }
}
