import XCTest
@testable import Sift

final class CleaningEngineTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureRoot: URL!
    private var savedExclusions: [String]?

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedExclusions = UserDefaults.standard.stringArray(forKey: CleanupExclusions.defaultsKey)
        UserDefaults.standard.set([], forKey: CleanupExclusions.defaultsKey)
        fixtureRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/PureMacTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot {
            try? fileManager.removeItem(at: fixtureRoot)
        }
        if let savedExclusions {
            UserDefaults.standard.set(savedExclusions, forKey: CleanupExclusions.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: CleanupExclusions.defaultsKey)
        }
        try super.tearDownWithError()
    }

    func testMissingFileIsHandledWithoutClaimingFreedSpace() async {
        let path = fixtureRoot.appendingPathComponent("already-gone").path
        let item = makeItem(path: path, size: 4096)

        let result = await CleaningEngine().cleanItems([item]) { _ in }

        XCTAssertTrue(result.cleanedPaths.contains(path))
        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertEqual(result.freedSpace, 0)
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testProgressAdvancesAfterDeletionFinishes() async throws {
        let file = fixtureRoot.appendingPathComponent("progress.bin")
        try Data(repeating: 1, count: 4096).write(to: file)
        let observed = expectation(description: "progress")

        let result = await CleaningEngine().cleanItems([makeItem(path: file.path, size: 4096)]) { progress in
            XCTAssertEqual(progress, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
            observed.fulfill()
        }

        await fulfillment(of: [observed], timeout: 1)
        XCTAssertEqual(result.itemsCleaned, 1)
        XCTAssertEqual(result.freedSpace, 4096)
    }

    func testSymlinkIsRefusedWithoutDeletingItsTarget() async throws {
        let target = fixtureRoot.appendingPathComponent("target.bin")
        let link = fixtureRoot.appendingPathComponent("linked.bin")
        try Data(repeating: 2, count: 4096).write(to: target)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        let result = await CleaningEngine().cleanItems([makeItem(path: link.path, size: 4096)]) { _ in }

        XCTAssertTrue(fileManager.fileExists(atPath: target.path))
        XCTAssertEqual(
            try fileManager.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType,
            .typeSymbolicLink
        )
        XCTAssertFalse(result.cleanedPaths.contains(link.path))
        XCTAssertFalse(result.skippedPaths.isEmpty)
    }

    func testSymlinkedParentIsRefusedWithoutDeletingItsTarget() async throws {
        let targetDirectory = fixtureRoot.appendingPathComponent("target-directory")
        let target = targetDirectory.appendingPathComponent("target.bin")
        let linkedDirectory = fixtureRoot.appendingPathComponent("linked-directory")
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 4096).write(to: target)
        try fileManager.createSymbolicLink(at: linkedDirectory, withDestinationURL: targetDirectory)
        let linkedTarget = linkedDirectory.appendingPathComponent("target.bin")

        let result = await CleaningEngine().cleanItems([makeItem(path: linkedTarget.path, size: 4096)]) { _ in }

        XCTAssertTrue(fileManager.fileExists(atPath: target.path))
        XCTAssertFalse(result.cleanedPaths.contains(linkedTarget.path))
        XCTAssertFalse(result.skippedPaths.isEmpty)
    }

    func testDanglingSymlinkIsRefusedInsteadOfReportedAsCleaned() async throws {
        let target = fixtureRoot.appendingPathComponent("missing-target.bin")
        let link = fixtureRoot.appendingPathComponent("dangling.bin")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        let result = await CleaningEngine().cleanItems([makeItem(path: link.path, size: 4096)]) { _ in }

        XCTAssertEqual(
            try fileManager.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType,
            .typeSymbolicLink
        )
        XCTAssertFalse(result.cleanedPaths.contains(link.path))
        XCTAssertFalse(result.skippedPaths.isEmpty)
    }

    func testExcludedFileIsNeverDeleted() async throws {
        let file = fixtureRoot.appendingPathComponent("excluded.bin")
        try Data(repeating: 3, count: 4096).write(to: file)
        CleanupExclusions.add(file.path)

        let result = await CleaningEngine().cleanItems([makeItem(path: file.path, size: 4096)]) { _ in }

        XCTAssertTrue(fileManager.fileExists(atPath: file.path))
        XCTAssertFalse(result.cleanedPaths.contains(file.path))
        XCTAssertEqual(result.skippedPaths[file.path], "Excluded from cleanup: excluded.bin")
    }

    func testAppModifyingCategoriesNeverFallThroughToFileDeletion() async throws {
        let app = fixtureRoot.appendingPathComponent("Protected.app")
        let localization = fixtureRoot.appendingPathComponent("fr.lproj")
        try fileManager.createDirectory(at: app, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: localization, withIntermediateDirectories: true)

        let items = [
            makeItem(path: app.path, size: 4096, category: .universalBinaries),
            makeItem(path: localization.path, size: 4096, category: .languageFiles),
        ]
        let result = await CleaningEngine().cleanItems(items) { _ in }

        XCTAssertTrue(fileManager.fileExists(atPath: app.path))
        XCTAssertTrue(fileManager.fileExists(atPath: localization.path))
        XCTAssertTrue(result.cleanedPaths.isEmpty)
        XCTAssertEqual(result.errors.count, 2)
    }

    func testTrashItemsAreNeverDeletedByTheGenericCleanPath() async throws {
        // Sits under ~/Library/Caches, an allow-listed root, so only the
        // category refusal can keep it alive.
        let file = fixtureRoot.appendingPathComponent("trashed.bin")
        try Data(repeating: 5, count: 4096).write(to: file)

        let result = await CleaningEngine().cleanItems([makeItem(path: file.path, size: 4096, category: .trash)]) { _ in }

        XCTAssertTrue(fileManager.fileExists(atPath: file.path))
        XCTAssertFalse(result.cleanedPaths.contains(file.path))
        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertEqual(result.freedSpace, 0)
        XCTAssertTrue(result.requiresAdmin.isEmpty)
        XCTAssertTrue(result.skippedPaths.values.contains { $0.contains("Trash") })
    }

    func testAdminPassRefusesTrashItemsBeforeEscalating() async throws {
        let file = fixtureRoot.appendingPathComponent("trashed-admin.bin")
        try Data(repeating: 6, count: 4096).write(to: file)

        let result = await CleaningEngine().cleanWithAdminPrivileges(
            items: [makeItem(path: file.path, size: 4096, category: .trash)]
        )

        XCTAssertTrue(fileManager.fileExists(atPath: file.path))
        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertTrue(result.errors.contains { $0.contains("Trash") })
    }

    func testLargeBatchReportsProgressAtMostOncePerPercent() async {
        let items = (0..<250).map { makeItem(path: fixtureRoot.appendingPathComponent("gone-\($0)").path, size: 1) }
        let recorder = FractionRecorder()

        _ = await CleaningEngine().cleanItems(items) { recorder.record($0) }

        let fractions = recorder.fractions
        XCTAssertLessThanOrEqual(fractions.count, 105)
        XCTAssertEqual(fractions.last, 1)
        XCTAssertEqual(fractions, fractions.sorted(), "Progress must never go backwards")
        XCTAssertEqual(Set(fractions).count, fractions.count, "No step may be reported twice")
    }

    func testSmallBatchStillReportsEveryStepItHas() async {
        let items = (0..<8).map { makeItem(path: fixtureRoot.appendingPathComponent("gone-small-\($0)").path, size: 1) }
        let recorder = FractionRecorder()

        _ = await CleaningEngine().cleanItems(items) { recorder.record($0) }

        XCTAssertEqual(recorder.fractions, (1...8).map { Double($0) / 8 })
    }

    func testEmptyBatchReportsNoProgress() async {
        let recorder = FractionRecorder()

        _ = await CleaningEngine().cleanItems([]) { recorder.record($0) }

        XCTAssertTrue(recorder.fractions.isEmpty)
    }

    func testBatchOfRefusedItemsStillReachesFullProgress() async {
        let items = (0..<120).map { makeItem(path: "/etc/sift-refused-\($0)", size: 1) }
        let recorder = FractionRecorder()

        _ = await CleaningEngine().cleanItems(items) { recorder.record($0) }

        XCTAssertEqual(recorder.fractions.last, 1)
        XCTAssertLessThanOrEqual(recorder.fractions.count, 105)
    }

    private func makeItem(
        path: String,
        size: Int64,
        category: CleaningCategory = .userCache
    ) -> CleanableItem {
        CleanableItem(
            name: (path as NSString).lastPathComponent,
            path: path,
            size: size,
            category: category,
            isSelected: true,
            lastModified: nil
        )
    }
    func testSingleFileAllowanceRefusesADirectoryInDownloads() async throws {
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("CleaningEngineHome-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let folder = home.appendingPathComponent("Downloads/a-folder", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_096).write(to: folder.appendingPathComponent("inside.bin"))
        defer { try? fileManager.removeItem(at: home) }

        let item = CleanableItem(
            name: "a-folder",
            path: folder.path,
            size: 4_096,
            category: .largeFiles,
            isSelected: true,
            lastModified: nil
        )

        let result = await CleaningEngine(homeDirectory: home, trashOperation: { _ in nil })
            .cleanItems([item]) { _ in }

        XCTAssertTrue(
            fileManager.fileExists(atPath: folder.path),
            "A directory must not pass the single-file allowance"
        )
        XCTAssertFalse(result.cleanedPaths.contains(folder.path))
    }

    func testSingleFileAllowanceStillAllowsARegularFile() async throws {
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("CleaningEngineHome-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? fileManager.removeItem(at: home) }

        var items: [CleanableItem] = []
        for folder in ["Downloads", "Documents", "Desktop"] {
            let directory = home.appendingPathComponent(folder, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("big.bin")
            try Data(repeating: 1, count: 4_096).write(to: file)
            items.append(CleanableItem(
                name: file.lastPathComponent,
                path: file.path,
                size: 4_096,
                category: .largeFiles,
                isSelected: true,
                lastModified: nil
            ))
        }

        let result = await CleaningEngine(homeDirectory: home, trashOperation: { _ in nil })
            .cleanItems(items) { _ in }

        XCTAssertEqual(result.freedSpace, 12_288)
        for item in items {
            XCTAssertFalse(fileManager.fileExists(atPath: item.path))
        }
    }

    func testSingleFileAllowanceRefusesDirectoriesInEveryPerFileRoot() async throws {
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("CleaningEngineHome-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? fileManager.removeItem(at: home) }

        var items: [CleanableItem] = []
        for folder in ["Downloads", "Documents", "Desktop"] {
            let directory = home.appendingPathComponent("\(folder)/a-folder", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 2, count: 4_096).write(to: directory.appendingPathComponent("inside.bin"))
            items.append(CleanableItem(
                name: "a-folder",
                path: directory.path,
                size: 4_096,
                category: .installers,
                isSelected: true,
                lastModified: nil
            ))
        }

        let result = await CleaningEngine(homeDirectory: home, trashOperation: { _ in nil })
            .cleanItems(items) { _ in }

        for item in items {
            XCTAssertTrue(fileManager.fileExists(atPath: item.path))
            XCTAssertFalse(result.cleanedPaths.contains(item.path))
        }
    }

    func testSingleFileAllowanceRefusesASymlinkInDesktop() async throws {
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("CleaningEngineHome-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer { try? fileManager.removeItem(at: home) }
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        try fileManager.createDirectory(at: desktop, withIntermediateDirectories: true)
        let target = desktop.appendingPathComponent("target.bin")
        try Data(repeating: 3, count: 4_096).write(to: target)
        let link = desktop.appendingPathComponent("linked.bin")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: target)

        let item = CleanableItem(
            name: link.lastPathComponent,
            path: link.path,
            size: 4_096,
            category: .largeFiles,
            isSelected: true,
            lastModified: nil
        )
        let result = await CleaningEngine(homeDirectory: home, trashOperation: { _ in nil })
            .cleanItems([item]) { _ in }

        XCTAssertTrue(fileManager.fileExists(atPath: target.path))
        XCTAssertFalse(result.cleanedPaths.contains(link.path))
    }

}

/// Thread-safe collector for progress fractions reported by CleaningEngine.
private final class FractionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []

    func record(_ fraction: Double) {
        lock.lock()
        values.append(fraction)
        lock.unlock()
    }

    var fractions: [Double] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

}
