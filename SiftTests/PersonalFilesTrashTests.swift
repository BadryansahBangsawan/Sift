import XCTest
@testable import Sift

/// Large & old files and Installers are the user's own downloads and media,
/// not regenerable junk: they leave through the Trash so they stay recoverable.
final class PersonalFilesTrashTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!
    private var savedDefaults: [String: Any] = [:]
    private var trashedPaths: [String] = []
    private let defaultsKeys = [
        "settings.cleaning.largeFileThreshold",
        "settings.cleaning.oldFileMonths",
        "settings.cleaning.largeFileExcludedFolders",
        "settings.cleaning.skipHiddenFiles",
        ScanEngine.treatICloudPlaceholdersAsFilesKey,
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        for key in defaultsKeys { savedDefaults[key] = UserDefaults.standard.object(forKey: key) }
        UserDefaults.standard.set(1, forKey: "settings.cleaning.largeFileThreshold")
        UserDefaults.standard.set(12, forKey: "settings.cleaning.oldFileMonths")
        UserDefaults.standard.removeObject(forKey: "settings.cleaning.largeFileExcludedFolders")
        UserDefaults.standard.set(true, forKey: "settings.cleaning.skipHiddenFiles")
        UserDefaults.standard.set(false, forKey: ScanEngine.treatICloudPlaceholdersAsFilesKey)

        home = fileManager.temporaryDirectory
            .appendingPathComponent("PureMac-PersonalFiles-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for path in trashedPaths { try? fileManager.removeItem(atPath: path) }
        if let home { try? fileManager.removeItem(at: home) }
        for key in defaultsKeys {
            if let value = savedDefaults[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        try super.tearDownWithError()
    }

    func testLargeFilesAndInstallersAreMarkedForTheTrash() async throws {
        try createFile("Downloads/holiday.mov", size: 2_000_000)
        try createFile(
            "Downloads/App.dmg",
            size: 2_000_000,
            modified: Date().addingTimeInterval(-30 * 24 * 60 * 60)
        )

        let largeFiles = await makeScanner().scanCategory(.largeFiles)
        let installers = await makeScanner().scanCategory(.installers)

        let video = try XCTUnwrap(largeFiles.items.first { $0.name == "holiday.mov" })
        let image = try XCTUnwrap(installers.items.first { $0.name == "App.dmg" })
        XCTAssertTrue(video.movesToTrash, "A video is the user's own file: it must be recoverable")
        XCTAssertTrue(image.movesToTrash, "A downloaded installer must be recoverable")
    }

    func testCleaningALargeFileMovesItToTheTrashWithoutCountingFreedSpace() async throws {
        let file = try createFile("Downloads/holiday.mov", size: 2_000_000)
        let scanned = await makeScanner().scanCategory(.largeFiles)
        var item = try XCTUnwrap(scanned.items.first { $0.name == file.lastPathComponent })
        item.isSelected = true

        let result = await makeCleaner().cleanItems([item]) { _ in }
        trashedPaths.append(contentsOf: result.trashedPaths)

        XCTAssertEqual(result.itemsCleaned, 1, "\(result.errors)")
        XCTAssertFalse(fileManager.fileExists(atPath: file.path), "The file leaves Downloads")
        XCTAssertEqual(result.trashedPaths.count, 1, "The bytes are still in the Trash, not unlinked")
        XCTAssertEqual(result.freedSpace, 0, "A Trash move reclaims nothing until the Trash is emptied")
    }

    // MARK: - Fixtures

    private func makeScanner() -> ScanEngine {
        ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false })
    }

    private func makeCleaner() -> CleaningEngine {
        CleaningEngine(homeDirectory: home, isAppRunning: { _ in false })
    }

    @discardableResult
    private func createFile(_ relative: String, size: Int, modified: Date = Date()) throws -> URL {
        let url = home.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: size).write(to: url)
        try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        return url
    }
}
