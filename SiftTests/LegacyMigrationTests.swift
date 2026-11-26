import XCTest
@testable import Sift

final class LegacyMigrationTests: XCTestCase {
    private var oldSuite: String!
    private var newSuite: String!
    private var root: URL!

    override func setUpWithError() throws {
        oldSuite = "test.legacy.old.\(UUID().uuidString)"
        newSuite = "test.legacy.new.\(UUID().uuidString)"
        root = FileManager.default.temporaryDirectory.appendingPathComponent("legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UserDefaults().removePersistentDomain(forName: oldSuite)
        UserDefaults().removePersistentDomain(forName: newSuite)
        try? FileManager.default.removeItem(at: root)
    }

    private func migrate() throws {
        let old = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        let new = try XCTUnwrap(UserDefaults(suiteName: newSuite))
        LegacyMigration.run(
            oldDefaults: old,
            newDefaults: new,
            oldSupport: root.appendingPathComponent("PureMac"),
            newSupport: root.appendingPathComponent("Sift")
        )
    }

    func testCopiesOldSettingsWithoutOverwritingNewOnes() throws {
        let old = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        old.set("dark", forKey: "PureMac.Appearance")
        old.set(true, forKey: "PureMac.OnboardingComplete")
        old.set(250, forKey: "settings.cleaning.largeFileThresholdMB")
        let new = try XCTUnwrap(UserDefaults(suiteName: newSuite))
        new.set("light", forKey: "PureMac.Appearance")

        try migrate()

        XCTAssertEqual(new.string(forKey: "PureMac.Appearance"), "light")
        XCTAssertTrue(new.bool(forKey: "PureMac.OnboardingComplete"))
        XCTAssertEqual(new.integer(forKey: "settings.cleaning.largeFileThresholdMB"), 250)
        XCTAssertEqual(old.string(forKey: "PureMac.Appearance"), "dark", "old settings stay in place")
    }

    func testRunsOnlyOnce() throws {
        let old = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        let new = try XCTUnwrap(UserDefaults(suiteName: newSuite))
        old.set("blue", forKey: "PureMac.Accent")
        try migrate()
        new.removeObject(forKey: "PureMac.Accent")

        try migrate()

        XCTAssertNil(new.string(forKey: "PureMac.Accent"), "a second launch must not re-import")
    }

    func testCopiesApplicationSupportWhenTheNewFolderIsMissing() throws {
        let oldFolder = root.appendingPathComponent("PureMac")
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: oldFolder.appendingPathComponent("cleanup-history.json"))

        try migrate()

        let copied = root.appendingPathComponent("Sift/cleanup-history.json")
        XCTAssertEqual(try String(contentsOf: copied, encoding: .utf8), "history")
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldFolder.appendingPathComponent("cleanup-history.json").path))
    }

    func testLeavesAnExistingNewFolderAlone() throws {
        let oldFolder = root.appendingPathComponent("PureMac")
        let newFolder = root.appendingPathComponent("Sift")
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldFolder.appendingPathComponent("a.json"))
        try Data("new".utf8).write(to: newFolder.appendingPathComponent("a.json"))

        try migrate()

        XCTAssertEqual(try String(contentsOf: newFolder.appendingPathComponent("a.json"), encoding: .utf8), "new")
    }

    func testNothingToMigrateIsHarmless() throws {
        try migrate()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sift").path))
    }

    func testDoesNotMarkDoneWhenTheCopyFails() throws {
        let oldFolder = root.appendingPathComponent("PureMac")
        try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
        try Data("history".utf8).write(to: oldFolder.appendingPathComponent("cleanup-history.json"))

        // A regular file where the destination's parent should be makes the
        // copy fail without touching any real Application Support folder.
        let blocker = root.appendingPathComponent("blocker")
        try Data("not a directory".utf8).write(to: blocker)
        let badNewSupport = blocker.appendingPathComponent("Sift")

        let old = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        let new = try XCTUnwrap(UserDefaults(suiteName: newSuite))
        old.set("dark", forKey: "PureMac.Appearance")

        LegacyMigration.run(
            oldDefaults: old,
            newDefaults: new,
            oldSupport: oldFolder,
            newSupport: badNewSupport
        )

        XCTAssertFalse(
            new.bool(forKey: LegacyMigration.doneKey),
            "A failed copy must be retried on the next launch"
        )
    }

}
