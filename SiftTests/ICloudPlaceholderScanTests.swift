import XCTest
@testable import Sift

final class ICloudPlaceholderScanTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureHome: URL!
    private let keys = [
        ScanEngine.treatICloudPlaceholdersAsFilesKey,
        "settings.cleaning.largeFileThreshold",
        "settings.cleaning.largeFileExcludedFolders",
    ]
    private var saved: [String: Any] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        fixtureHome = fileManager.temporaryDirectory
            .appendingPathComponent("ICloudPlaceholderScanTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixtureHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureHome { try? fileManager.removeItem(at: fixtureHome) }
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try super.tearDownWithError()
    }

    func testPlaceholdersAreSkippedUnlessTheSettingCountsThem() {
        XCTAssertEqual(ScanEngine.treatICloudPlaceholdersAsFilesKey, "settings.cleaning.treatICloudPlaceholdersAsFiles")

        XCTAssertFalse(ScanEngine.includesFile(isUbiquitous: true, downloadingStatus: .notDownloaded, treatICloudPlaceholdersAsFiles: false))
        XCTAssertTrue(ScanEngine.includesFile(isUbiquitous: true, downloadingStatus: .notDownloaded, treatICloudPlaceholdersAsFiles: true))
    }

    func testLocalAndDownloadedFilesAlwaysCount() {
        for treat in [false, true] {
            XCTAssertTrue(ScanEngine.includesFile(isUbiquitous: nil, downloadingStatus: nil, treatICloudPlaceholdersAsFiles: treat))
            XCTAssertTrue(ScanEngine.includesFile(isUbiquitous: false, downloadingStatus: nil, treatICloudPlaceholdersAsFiles: treat))
            XCTAssertTrue(ScanEngine.includesFile(isUbiquitous: true, downloadingStatus: .current, treatICloudPlaceholdersAsFiles: treat))
            XCTAssertTrue(ScanEngine.includesFile(isUbiquitous: true, downloadingStatus: .downloaded, treatICloudPlaceholdersAsFiles: treat))
        }
    }

    func testLargeFileScanKeepsLocalFilesInBothModes() async throws {
        let downloads = fixtureHome.appendingPathComponent("Downloads", isDirectory: true)
        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2 * 1024 * 1024 + 1).write(to: downloads.appendingPathComponent("local.bin"))
        UserDefaults.standard.set(1, forKey: "settings.cleaning.largeFileThreshold")
        UserDefaults.standard.removeObject(forKey: "settings.cleaning.largeFileExcludedFolders")

        for treat in [false, true] {
            UserDefaults.standard.set(treat, forKey: ScanEngine.treatICloudPlaceholdersAsFilesKey)
            let result = await ScanEngine(homeDirectory: fixtureHome).scanCategory(.largeFiles)
            XCTAssertEqual(result.items.map(\.name), ["local.bin"], "treatICloudPlaceholdersAsFiles = \(treat)")
        }
    }
}
