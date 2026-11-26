import XCTest
@testable import Sift
import Darwin

final class SystemJunkTmpPolicyTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixtureRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureRoot = fileManager.temporaryDirectory
            .appendingPathComponent("SiftTmp-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try fileManager.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixtureRoot { try? fileManager.removeItem(at: fixtureRoot) }
        try super.tearDownWithError()
    }

    // MARK: - Scan

    func testFreshTmpEntryIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("fresh", isDirectory: true)
        try fileManager.createDirectory(at: entry, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 8_192).write(to: entry.appendingPathComponent("a.bin"))

        let items = await scanTmpItems()

        XCTAssertFalse(items.contains { $0.path == entry.path })
    }

    func testTmpEntryWithRecentFileDeepInsideIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("deep-recent", isDirectory: true)
        let deep = entry.appendingPathComponent("a/b/c", isDirectory: true)
        try fileManager.createDirectory(at: deep, withIntermediateDirectories: true)
        let inner = deep.appendingPathComponent("live.bin")
        try Data(repeating: 2, count: 8_192).write(to: inner)
        try ageTree(entry, by: days(5))
        try fileManager.setAttributes([.modificationDate: Date().addingTimeInterval(-3_600)], ofItemAtPath: inner.path)

        let items = await scanTmpItems()

        XCTAssertFalse(items.contains { $0.path == entry.path })
    }

    func testTmpRepositoryIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("worktree", isDirectory: true)
        let git = entry.appendingPathComponent(".git", isDirectory: true)
        try fileManager.createDirectory(at: git, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 8_192).write(to: entry.appendingPathComponent("work.bin"))
        try ageTree(entry, by: days(5))

        let items = await scanTmpItems()

        XCTAssertFalse(items.contains { $0.path == entry.path })
    }

    func testTmpEntryWithSocketIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("service", isDirectory: true)
        try fileManager.createDirectory(at: entry, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 8_192).write(to: entry.appendingPathComponent("a.bin"))
        XCTAssertTrue(makeSocket(at: entry.appendingPathComponent("live.sock")))
        try ageTree(entry, by: days(5))

        let items = await scanTmpItems()

        XCTAssertFalse(items.contains { $0.path == entry.path })
    }

    func testStalePlainTmpEntryIsOfferedUnselected() async throws {
        let entry = fixtureRoot.appendingPathComponent("old-scratch", isDirectory: true)
        try fileManager.createDirectory(at: entry, withIntermediateDirectories: true)
        try Data(repeating: 5, count: 8_192).write(to: entry.appendingPathComponent("a.bin"))
        try ageTree(entry, by: days(5))

        let items = await scanTmpItems()

        let item = try XCTUnwrap(items.first { $0.path == entry.path })
        XCTAssertFalse(item.isSelected)
        XCTAssertEqual(item.category, .systemJunk)
    }

    // MARK: - Cleaner re-check

    func testCleanerSkipsTmpEntryThatBecameActiveAfterTheScan() async throws {
        // The cleaner only re-checks paths under the real managed roots, so
        // this fixture lives in /private/tmp under a unique name.
        let entry = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("sift-policy-test-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: entry, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: entry) }
        let inner = entry.appendingPathComponent("a.bin")
        try Data(repeating: 6, count: 8_192).write(to: inner)
        try ageTree(entry, by: days(5))

        XCTAssertTrue(TmpJunkPolicy.inspect(path: entry.path, now: Date()).isOfferable)

        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: inner.path)
        let recheck = TmpJunkPolicy.inspect(path: entry.path, now: Date())
        XCTAssertFalse(recheck.isOfferable, "newest: \(String(describing: recheck.newestModification)), git: \(recheck.containsGit), socket: \(recheck.containsSocket), capped: \(recheck.hitWalkCap), reason: \(String(describing: recheck.rejectionReason))")
        XCTAssertTrue(
            TmpJunkPolicy.contains(entry.path),
            "path=\(entry.path) normalized=\((entry.path as NSString).standardizingPath) roots=\(TmpJunkPolicy.roots)"
        )
        let item = CleanableItem(
            name: entry.lastPathComponent,
            path: entry.path,
            size: 8_192,
            category: .systemJunk,
            isSelected: false,
            lastModified: nil
        )

        let result = await CleaningEngine().cleanItems([item]) { _ in }

        XCTAssertEqual(result.itemsCleaned, 0)
        XCTAssertTrue(result.cleanedPaths.isEmpty)
        XCTAssertTrue(result.skippedPaths.values.contains { $0.contains("three days") })
        XCTAssertTrue(fileManager.fileExists(atPath: entry.path))
    }

    func testTmpWorktreeRootWithGitFileIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("linked-worktree", isDirectory: true)
        try fileManager.createDirectory(at: entry, withIntermediateDirectories: true)
        try Data("gitdir: /private/tmp/main/.git/worktrees/linked-worktree\n".utf8)
            .write(to: entry.appendingPathComponent(".git"))
        try Data(repeating: 7, count: 8_192).write(to: entry.appendingPathComponent("work.bin"))
        try ageTree(entry, by: days(5))

        let items = await scanTmpItems()

        XCTAssertFalse(items.contains { $0.path == entry.path })
    }

    func testTmpFolderHoldingWorktreesOneAndTwoLevelsDownIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("worktree-collection", isDirectory: true)
        let one = entry.appendingPathComponent("one", isDirectory: true)
        let two = entry.appendingPathComponent("nested/two", isDirectory: true)
        try fileManager.createDirectory(at: one, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: two, withIntermediateDirectories: true)
        try Data("gitdir: /private/tmp/main/.git/worktrees/one\n".utf8)
            .write(to: one.appendingPathComponent(".git"))
        try Data("gitdir: /private/tmp/main/.git/worktrees/two\n".utf8)
            .write(to: two.appendingPathComponent(".git"))
        try Data(repeating: 8, count: 8_192).write(to: one.appendingPathComponent("a.bin"))
        try Data(repeating: 9, count: 8_192).write(to: two.appendingPathComponent("b.bin"))
        try ageTree(entry, by: days(5))

        let items = await scanTmpItems()

        XCTAssertFalse(items.contains { $0.path == entry.path })
    }

    func testTmpWorktreeWithLargeOldDependenciesIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("worktree-deps", isDirectory: true)
        let nodeModules = entry.appendingPathComponent("node_modules/pkg", isDirectory: true)
        let dist = entry.appendingPathComponent("dist", isDirectory: true)
        try fileManager.createDirectory(at: nodeModules, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: dist, withIntermediateDirectories: true)
        try Data("gitdir: /private/tmp/main/.git/worktrees/deps\n".utf8)
            .write(to: entry.appendingPathComponent(".git"))
        try Data(repeating: 10, count: 64_000).write(to: nodeModules.appendingPathComponent("index.js"))
        try Data(repeating: 11, count: 64_000).write(to: dist.appendingPathComponent("bundle.js"))
        try ageTree(entry, by: days(5))

        let items = await scanTmpItems()

        XCTAssertFalse(items.contains { $0.path == entry.path })
    }

    func testTmpWorktreeNestedDeeperThanInspectionDepthIsNotOffered() async throws {
        let entry = fixtureRoot.appendingPathComponent("deep-worktree", isDirectory: true)
        // entry/a/b/worktree/.git is level 4 below the entry, past the old
        // gitInspectionDepth of 3.
        let worktree = entry.appendingPathComponent("a/b/worktree", isDirectory: true)
        try fileManager.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("gitdir: /private/tmp/main/.git/worktrees/deep\n".utf8)
            .write(to: worktree.appendingPathComponent(".git"))
        try Data(repeating: 12, count: 8_192).write(to: worktree.appendingPathComponent("work.bin"))
        try ageTree(entry, by: days(5))

        let items = await scanTmpItems()

        XCTAssertFalse(
            items.contains { $0.path == entry.path },
            "a worktree nested four levels down is still live work"
        )
    }

    // MARK: - Helpers

    private func scanTmpItems() async -> [CleanableItem] {
        let result = await ScanEngine(
            homeDirectory: fixtureRoot,
            tmpRoots: [fixtureRoot.path],
            now: Date.init
        ).scanCategory(.systemJunk)
        return result.items.filter { $0.path.hasPrefix(fixtureRoot.path + "/") }
    }

    private func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 24 * 60 * 60 }

    private func ageTree(_ url: URL, by interval: TimeInterval) throws {
        let date = Date().addingTimeInterval(-interval)
        try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        guard let enumerator = fileManager.enumerator(atPath: url.path) else { return }
        for case let relative as String in enumerator {
            try fileManager.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: url.appendingPathComponent(relative).path
            )
        }
    }

    private func makeSocket(at url: URL) -> Bool {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = url.path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                for (index, byte) in pathBytes.enumerated() { destination[index] = byte }
            }
        }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return bound == 0
    }
}
