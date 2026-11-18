import XCTest
@testable import Sift

/// Safety invariants of the AI tools category, exercised through the public
/// ScanEngine/CleaningEngine seam with a disposable HOME.
final class AIToolCleanupTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!
    private let claudeBundleID = AIToolCleanupCatalog.claudeBundleID

    override func setUpWithError() throws {
        home = fileManager.temporaryDirectory
            .appendingPathComponent("PureMac-AITools-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home, fileManager.fileExists(atPath: home.path) {
            try fileManager.removeItem(at: home)
        }
    }

    func testCachesArePreselectedAndHistoryIsOptIn() async throws {
        try createFile("Library/Application Support/Claude/Cache/data.bin")
        try createFile("Library/Application Support/Claude/vm_bundles/image.bin")
        try createFile(".claude/shell-snapshots/snapshot.sh")
        try createFile(".omp/logs/omp.log")
        try createFile(".claude/file-history/history.jsonl")
        let session = try createSession(
            ".claude/projects/-Users-test-demo/11111111-1111-1111-1111-111111111111.jsonl",
            modified: oldDate
        )

        let scan = await makeScanner().scanCategory(.aiApps)
        let byPath = Dictionary(uniqueKeysWithValues: scan.items.map { ($0.path, $0) })

        XCTAssertEqual(byPath[path("Library/Application Support/Claude/Cache")]?.isSelected, true)
        XCTAssertEqual(byPath[path(".claude/shell-snapshots")]?.isSelected, true)
        XCTAssertEqual(byPath[path(".omp/logs")]?.isSelected, true)

        XCTAssertEqual(byPath[path("Library/Application Support/Claude/vm_bundles")]?.isSelected, false)
        XCTAssertEqual(byPath[path(".claude/file-history")]?.isSelected, false)
        XCTAssertEqual(byPath[session]?.isSelected, false)
        XCTAssertEqual(byPath[session]?.movesToTrash, true)
        XCTAssertNotNil(byPath[session]?.note)
    }

    func testNeverTouchPathsAreNeverItemsAndAreRefusedByCleaner() async throws {
        let forbidden = [
            ".claude/settings.json",
            ".claude/CLAUDE.md",
            ".claude/keybindings.json",
            ".claude/.credentials.json",
            ".claude/skills/ts/SKILL.md",
            ".claude/plugins/plugin/index.js",
            ".claude/hooks/notify.sh",
            ".claude/projects/-Users-test-demo/memory/notes.md",
            ".omp/agent/config.yml",
            ".omp/agent/agent.db",
            ".omp/agent/AGENTS.md",
            ".omp/agent/extensions/ext.js",
            ".codex/config.toml",
            ".codex/auth.json",
        ]
        for relative in forbidden {
            try createFile(relative, size: 2048)
        }

        let scan = await makeScanner().scanCategory(.aiApps)
        for item in scan.items {
            for forbiddenPath in forbidden.map(path) {
                XCTAssertNotEqual(item.path, forbiddenPath)
                XCTAssertFalse(
                    forbiddenPath.hasPrefix(item.path + "/"),
                    "Item \(item.path) would remove never-touch path \(forbiddenPath)"
                )
            }
        }

        let items = forbidden.map { aiItem(relative: $0) }
        let result = await makeCleaner().cleanItems(items) { _ in }

        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertEqual(result.errors.count, forbidden.count)
        for relative in forbidden {
            XCTAssertTrue(fileManager.fileExists(atPath: path(relative)), "\(relative) was removed")
        }
    }

    func testSessionRemovesTranscriptAndCompanionFolderTogether() async throws {
        let transcript = try createSession(
            ".claude/projects/-Users-test-demo/22222222-2222-2222-2222-222222222222.jsonl",
            modified: oldDate
        )
        let companion = transcript.replacingOccurrences(of: ".jsonl", with: "")
        try createFile(
            ".claude/projects/-Users-test-demo/22222222-2222-2222-2222-222222222222/step.log"
        )

        let scan = await makeScanner().scanCategory(.aiApps)
        let session = try XCTUnwrap(scan.items.first { $0.path == transcript })
        XCTAssertEqual(session.companionPaths, [companion])

        let result = await makeCleaner().cleanItems([session]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 1)
        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)")
        XCTAssertFalse(fileManager.fileExists(atPath: transcript))
        XCTAssertFalse(fileManager.fileExists(atPath: companion))
        XCTAssertFalse(result.trashedPaths.isEmpty, "Opt-in history must be moved to the Trash, not unlinked")
    }

    func testTrashedHistoryIsNotCountedAsFreedSpace() async throws {
        let transcript = try createSession(
            ".claude/projects/-Users-test-demo/66666666-6666-6666-6666-666666666666.jsonl",
            modified: oldDate
        )
        let scan = await makeScanner().scanCategory(.aiApps)
        let session = try XCTUnwrap(scan.items.first { $0.path == transcript })
        XCTAssertTrue(session.movesToTrash)

        let result = await makeCleaner().cleanItems([session]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 1)
        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)")
        XCTAssertFalse(result.trashedPaths.isEmpty, "Opt-in history must be moved to the Trash")
        XCTAssertEqual(
            result.freedSpace,
            0,
            "A file moved to the Trash still occupies disk; counting it as freed double-counts when the Trash is emptied"
        )
    }

    func testUnlinkedAICacheStillCountsAsFreedSpace() async throws {
        try createFile(".claude/shell-snapshots/snapshot.sh")
        let cachePath = path(".claude/shell-snapshots")
        let scan = await makeScanner().scanCategory(.aiApps)
        let cache = try XCTUnwrap(scan.items.first { $0.path == cachePath })
        XCTAssertFalse(cache.movesToTrash)

        let result = await makeCleaner().cleanItems([cache]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 1)
        XCTAssertTrue(result.errors.isEmpty, "\(result.errors)")
        XCTAssertEqual(result.freedSpace, cache.size)
        XCTAssertTrue(result.trashedPaths.isEmpty)
    }

    func testMixedBatchFreesOnlyTheUnlinkedBytes() async throws {
        try createFile(".claude/shell-snapshots/snapshot.sh")
        try createSession(
            ".claude/projects/-Users-test-demo/77777777-7777-7777-7777-777777777777.jsonl",
            modified: oldDate
        )
        let cachePath = path(".claude/shell-snapshots")
        let scan = await makeScanner().scanCategory(.aiApps)
        let cache = try XCTUnwrap(scan.items.first { $0.path == cachePath })
        let session = try XCTUnwrap(
            scan.items.first {
                $0.path == path(".claude/projects/-Users-test-demo/77777777-7777-7777-7777-777777777777.jsonl")
            }
        )

        let result = await makeCleaner().cleanItems([cache, session]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 2)
        XCTAssertEqual(result.freedSpace, cache.size)
        XCTAssertFalse(result.trashedPaths.isEmpty)
    }

    func testRefusedAIItemFreesNothing() async throws {
        let transcript = try createSession(
            ".claude/projects/-Users-test-demo/88888888-8888-8888-8888-888888888888.jsonl",
            modified: oldDate
        )
        try createFile(".claude/settings.json", size: 2048)

        var item = aiItem(relative: ".claude/projects/-Users-test-demo/88888888-8888-8888-8888-888888888888.jsonl")
        item.companionPaths = [path(".claude/settings.json")]

        let result = await makeCleaner().cleanItems([item]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertEqual(result.freedSpace, 0)
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: transcript))
    }

    func testSessionModifiedJustNowIsNotOffered() async throws {
        _ = try createSession(
            ".claude/projects/-Users-test-demo/33333333-3333-3333-3333-333333333333.jsonl",
            modified: fixedNow.addingTimeInterval(-60)
        )
        let old = try createSession(
            ".claude/projects/-Users-test-demo/44444444-4444-4444-4444-444444444444.jsonl",
            modified: oldDate
        )

        let scan = await makeScanner().scanCategory(.aiApps)
        let sessionPaths = scan.items.map(\.path).filter { $0.hasSuffix(".jsonl") }
        XCTAssertEqual(sessionPaths, [old])
    }

    func testVMImageIsSkippedWhileClaudeRuns() async throws {
        try createFile("Library/Application Support/Claude/vm_bundles/image.bin")
        let vmPath = path("Library/Application Support/Claude/vm_bundles")
        let scan = await makeScanner().scanCategory(.aiApps)
        let vmItem = try XCTUnwrap(scan.items.first { $0.path == vmPath })
        XCTAssertEqual(vmItem.isSelected, false)

        let running = CleaningEngine(homeDirectory: home, isAppRunning: { _ in true })
        let skipped = await running.cleanItems([vmItem]) { _ in }
        XCTAssertEqual(skipped.itemsCleaned, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: vmPath))
        XCTAssertTrue(skipped.errors.contains { $0.contains("Claude is running") }, "\(skipped.errors)")

        let idle = CleaningEngine(homeDirectory: home, isAppRunning: { _ in false })
        let cleaned = await idle.cleanItems([vmItem]) { _ in }
        XCTAssertEqual(cleaned.itemsCleaned, 1)
        XCTAssertFalse(fileManager.fileExists(atPath: vmPath))
    }

    func testSessionWithForeignCompanionIsRefused() async throws {
        let transcript = try createSession(
            ".claude/projects/-Users-test-demo/55555555-5555-5555-5555-555555555555.jsonl",
            modified: oldDate
        )
        try createFile(".claude/settings.json", size: 2048)
        try createFile("precious.txt", size: 2048)

        var item = aiItem(relative: ".claude/projects/-Users-test-demo/55555555-5555-5555-5555-555555555555.jsonl")
        item.companionPaths = [path(".claude/settings.json")]
        var second = item
        second.companionPaths = [path("precious.txt")]

        let result = await makeCleaner().cleanItems([item, second]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertEqual(result.errors.count, 2)
        XCTAssertTrue(fileManager.fileExists(atPath: transcript))
        XCTAssertTrue(fileManager.fileExists(atPath: path(".claude/settings.json")))
        XCTAssertTrue(fileManager.fileExists(atPath: path("precious.txt")))
    }

    func testAIToolsStayInSmartScanButOptInHistoryCannotBeAutoCleaned() {
        XCTAssertTrue(CleaningCategory.scannable.contains(.aiApps))
        XCTAssertTrue(CleaningCategory.smartScanCategories.contains(.aiApps))
        XCTAssertFalse(CleaningCategory.systemJunkGroup.contains(.aiApps))
        for spec in AIToolCleanupCatalog.specs(home: home.path) where spec.isOptIn {
            XCTAssertNotNil(spec.note, "Opt-in \(spec.path) needs a reason shown in the row")
        }
    }

    func testCleanerRefusesATranscriptThatBecameActiveAfterTheScan() async throws {
        // The scan offers only sessions untouched for ten minutes. The user can
        // resume one between the scan and the click, and that transcript is
        // live work, not history: the cleaner must re-check, like it re-checks
        // the temp-entry policy and the Claude-running guard.
        let relative = ".claude/projects/-Users-test-demo/22222222-2222-2222-2222-222222222222.jsonl"
        let transcript = try createSession(relative, modified: oldDate)
        let item = CleanableItem(
            name: "demo session",
            path: transcript,
            size: 4096,
            category: .aiApps,
            isSelected: true,
            lastModified: oldDate,
            companionPaths: AIToolCleanupCatalog.sessionCompanions(for: transcript),
            note: nil,
            movesToTrash: true
        )
        try fileManager.setAttributes([.modificationDate: fixedNow], ofItemAtPath: transcript)

        let result = await makeCleaner().cleanItems([item]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertTrue(fileManager.fileExists(atPath: transcript), "A live session must stay where its agent writes it")
        XCTAssertTrue(result.trashedPaths.isEmpty)
        XCTAssertTrue(result.errors.contains { $0.localizedCaseInsensitiveContains("open") }, "\(result.errors)")
    }

    // MARK: - Fixtures

    private var fixedNow: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    private var oldDate: Date { fixedNow.addingTimeInterval(-86_400) }

    private func makeScanner() -> ScanEngine {
        ScanEngine(
            homeDirectory: home,
            tmpRoots: [],
            now: { self.fixedNow },
            isAppRunning: { _ in false }
        )
    }

    private func makeCleaner() -> CleaningEngine {
        CleaningEngine(homeDirectory: home, isAppRunning: { _ in false })
    }

    private func path(_ relative: String) -> String {
        home.appendingPathComponent(relative).path
    }

    private func createDirectory(_ relative: String) throws {
        try fileManager.createDirectory(atPath: path(relative), withIntermediateDirectories: true)
    }

    private func createFile(_ relative: String, size: Int = 4096, modified: Date? = nil) throws {
        let url = URL(fileURLWithPath: path(relative))
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: size).write(to: url)
        if let modified {
            try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
    }

    @discardableResult
    private func createSession(_ relative: String, modified: Date) throws -> String {
        try createFile(relative, modified: modified)
        return path(relative)
    }

    private func aiItem(relative: String) -> CleanableItem {
        CleanableItem(
            name: relative,
            path: path(relative),
            size: 4096,
            category: .aiApps,
            isSelected: true,
            lastModified: nil
        )
    }
}
