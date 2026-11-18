import Foundation
import XCTest
@testable import sift

final class OptimizeConfigTests: XCTestCase {
    func testSnapshotParserAcceptsOnlyExactTimeMachineSnapshots() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-09-13-235959.local
        com.apple.os.update-123456
        com.apple.TimeMachine.2026-02-30-120000.local
        com.apple.TimeMachine.2026-09-14-090102.local extra
        com.apple.TimeMachine.2026-09-14-090102.local
        com.apple.TimeMachine.2026-09-14-090102.local
        """

        XCTAssertEqual(
            Optimize.parseLocalSnapshots(output),
            [
                "com.apple.TimeMachine.2026-09-14-090102.local",
                "com.apple.TimeMachine.2026-09-13-235959.local",
            ]
        )
    }

    func testLegacyOptimizeViewsRemainRecognized() throws {
        XCTAssertEqual(try Optimize.parse(["ram"]).task, "ram")
        XCTAssertEqual(try Optimize.parse(["purgeable"]).task, "purgeable")
        XCTAssertEqual(try Optimize.parse(["snapshots"]).task, "snapshots")
        XCTAssertNil(try Optimize.parse([]).task)
    }

    func testUptimeFormatting() {
        XCTAssertEqual(Optimize.formatUptime(0), "0m")
        XCTAssertEqual(Optimize.formatUptime(3_661), "1h 1m")
        XCTAssertEqual(Optimize.formatUptime(176_461), "2d 1h 1m")
    }

    func testManagedCapacityNeverBecomesNegative() {
        XCTAssertEqual(
            VolumeStatus(availableNow: 50, availableForImportantUsage: 80, total: 100)
                .systemManagedCapacity,
            30
        )
        XCTAssertEqual(
            VolumeStatus(availableNow: 80, availableForImportantUsage: 50, total: 100)
                .systemManagedCapacity,
            0
        )
    }

    func testConfigStoreValidatesAndPersistsToInjectedFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings/config.json")

        var store = try ConfigStore(fileURL: file)
        try store.set("purge.older_than_days", " 14 ")
        XCTAssertEqual(store.values["purge.older_than_days"], "14")

        let reloaded = try ConfigStore(fileURL: file)
        XCTAssertEqual(reloaded.values["purge.older_than_days"], "14")
        XCTAssertThrowsError(try store.set("purge.older_than_days", "0"))
        XCTAssertThrowsError(try store.set("purge.older_than_days", "3651"))
        XCTAssertThrowsError(try store.set("unknown", "14"))
    }

    func testMalformedConfigAndPersistenceFailuresAreReported() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let malformed = directory.appendingPathComponent("malformed.json")
        try Data("[]".utf8).write(to: malformed)
        XCTAssertThrowsError(try ConfigStore(fileURL: malformed))

        let blocker = directory.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocker)
        var store = try ConfigStore(fileURL: blocker.appendingPathComponent("config.json"))
        XCTAssertThrowsError(try store.set("purge.older_than_days", "14"))
        XCTAssertTrue(store.values.isEmpty)
    }

    func testIgnoreStoreUsesInjectedFileAndRollsBackFailedSave() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings/ignore")
        let protected = directory.appendingPathComponent("protected").path

        var store = try IgnoreStore(fileURL: file)
        XCTAssertTrue(try store.add(protected))
        XCTAssertTrue(store.isIgnored(protected + "/child"))
        XCTAssertEqual(try IgnoreStore(fileURL: file).roots, [protected])

        let blocker = directory.appendingPathComponent("blocked")
        try Data("file".utf8).write(to: blocker)
        var blocked = try IgnoreStore(fileURL: blocker.appendingPathComponent("ignore"))
        XCTAssertThrowsError(try blocked.add(protected))
        XCTAssertTrue(blocked.roots.isEmpty)
    }

    func testStoresFallBackToLegacyPureMacFilesAndSaveToNewPath() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacyIgnore = directory.appendingPathComponent("puremac/ignore")
        let legacyConfig = directory.appendingPathComponent("puremac/config.json")
        let newIgnore = directory.appendingPathComponent("sift/ignore")
        let newConfig = directory.appendingPathComponent("sift/config.json")
        let protected = directory.appendingPathComponent("protected").path
        try FileManager.default.createDirectory(
            at: legacyIgnore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data((protected + "\n").utf8).write(to: legacyIgnore)
        try Data(#"{"purge.older_than_days":"21"}"#.utf8).write(to: legacyConfig)

        // Only the legacy files exist: they are read.
        var ignore = try IgnoreStore(fileURL: newIgnore, legacyFileURL: legacyIgnore)
        XCTAssertEqual(ignore.roots, [protected])
        var config = try ConfigStore(fileURL: newConfig, legacyFileURL: legacyConfig)
        XCTAssertEqual(config.values["purge.older_than_days"], "21")

        // Saving writes the merged data to the new path and leaves the legacy file alone.
        let extra = directory.appendingPathComponent("extra").path
        XCTAssertTrue(try ignore.add(extra))
        try config.set("purge.older_than_days", "30")
        XCTAssertEqual(try IgnoreStore(fileURL: newIgnore).roots, [extra, protected].sorted())
        XCTAssertEqual(try ConfigStore(fileURL: newConfig).values["purge.older_than_days"], "30")
        XCTAssertEqual(try IgnoreStore(fileURL: legacyIgnore).roots, [protected])

        // Once the new file exists it wins over the legacy one.
        XCTAssertEqual(
            try ConfigStore(fileURL: newConfig, legacyFileURL: legacyConfig).values["purge.older_than_days"],
            "30"
        )
    }

    func testRelativeIgnorePathBecomesAbsoluteAndProtectsCandidate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workingDirectory = directory.appendingPathComponent("working", isDirectory: true)
        let candidate = workingDirectory.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)

        var store = try IgnoreStore(
            fileURL: directory.appendingPathComponent("ignore"),
            currentDirectoryPath: workingDirectory.path
        )
        XCTAssertTrue(try store.add("./cache"))
        XCTAssertFalse(try store.add("nested/../cache"))
        XCTAssertEqual(store.roots, [candidate.path])
        XCTAssertFalse(Safety.canRemove(candidate.path, ignore: store).ok)
    }

    func testIgnoreStoreRejectsControlCharactersAndSkipsMalformedFileEntries() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("ignore")
        var store = try IgnoreStore(fileURL: file, currentDirectoryPath: directory.path)

        for path in ["", "one\ntwo", "one\rtwo", "one\0two"] {
            XCTAssertThrowsError(try store.add(path))
            XCTAssertThrowsError(try store.remove(path))
        }
        XCTAssertTrue(store.roots.isEmpty)
        var rootStore = try IgnoreStore(fileURL: file, currentDirectoryPath: "/")
        for path in [".", "/.", "/tmp/.."] {
            XCTAssertThrowsError(try rootStore.add(path))
            XCTAssertThrowsError(try rootStore.remove(path))
        }
        XCTAssertTrue(rootStore.roots.isEmpty)
        XCTAssertTrue(try rootStore.add("/tmp/./sift-ignore-fixture"))
        XCTAssertEqual(rootStore.roots, ["/tmp/sift-ignore-fixture"])
        XCTAssertTrue(try rootStore.remove("/tmp/sift-ignore-fixture"))

        // One bad hand-edited line must not drop the protections beside it: the
        // loader warns and keeps every valid entry.
        let validLine = "/tmp/./sift-ignore-fixture"
        for invalidLine in [
            "relative/path",
            "/.",
            "/tmp/..",
            "/tmp/bad\u{0}path",
            "/tmp/bad\rpath"
        ] {
            try Data("\(invalidLine)\n\(validLine)\n".utf8).write(to: file)
            let loaded = try IgnoreStore(fileURL: file)
            XCTAssertEqual(loaded.roots, ["/tmp/sift-ignore-fixture"])
        }
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-cli-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
