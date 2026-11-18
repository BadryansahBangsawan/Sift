import XCTest
@testable import Sift

/// The cleaner deliberately leaves some rows alone: a temp entry that turned
/// live, Claude running, a session the user resumed, an excluded path. Those are
/// not permission problems, and reporting them as "N item(s) need Full Disk
/// Access" sends the user into a Grant Access loop that can never succeed.
@MainActor
final class PolicySkipReportingTests: XCTestCase {
    private let fileManager = FileManager.default
    private var home: URL!

    override func setUpWithError() throws {
        home = fileManager.temporaryDirectory
            .appendingPathComponent("PureMac-PolicySkip-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let home, fileManager.fileExists(atPath: home.path) {
            try fileManager.removeItem(at: home)
        }
    }

    func testOpenSessionSkipIsNotReportedAsNeedingFullDiskAccess() async throws {
        let transcript = try makeTranscript()
        let scan = await makeScanner().scanCategory(.aiApps)
        let session = try XCTUnwrap(scan.items.first { $0.path == transcript })
        // The user resumes the session between the scan and the click.
        let fresh = (try? fileManager.attributesOfItem(atPath: transcript)[.modificationDate] as? Date)
            ?? Date()
        try fileManager.setAttributes(
            [.modificationDate: fresh.addingTimeInterval(120)],
            ofItemAtPath: transcript
        )

        let state = makeState()
        state.categoryResults[.aiApps] = CategoryResult(
            category: .aiApps,
            items: [session],
            totalSize: session.size
        )

        state.cleanAll()
        await waitForClean(state)

        XCTAssertTrue(
            state.pendingPermissionRetryItems.isEmpty,
            "An open session is not an item Full Disk Access could remove"
        )
        XCTAssertFalse(state.cleanErrorIsFDAFixable)
        XCTAssertEqual(
            state.cleanError,
            String(localized: "Skipped: this session is open. Quit the session and scan again."),
            "The user must see the real reason, not a permission prompt"
        )
        XCTAssertFalse(state.lastCleanupHadFailures, "A deliberate skip is not a failed cleanup")
    }

    func testTemporaryEntryThatTurnedLiveIsReportedAsSkipped() async throws {
        // A temp entry holding a git repository is deliberately skipped: it is
        // live work, not a permission problem.
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("PureMac-PolicySkip-tmp-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: folder.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 8192).write(to: folder.appendingPathComponent("blob.bin"))
        defer { try? fileManager.removeItem(at: folder) }

        let item = CleanableItem(
            name: folder.lastPathComponent,
            path: folder.path,
            size: 8192,
            category: .systemJunk,
            isSelected: true,
            lastModified: nil
        )

        let state = makeState()
        state.categoryResults[.systemJunk] = CategoryResult(category: .systemJunk, items: [item], totalSize: 8192)

        state.cleanAll()
        await waitForClean(state)

        XCTAssertTrue(
            state.pendingPermissionRetryItems.isEmpty,
            "A policy skip cannot be fixed by granting Full Disk Access"
        )
        XCTAssertFalse(state.cleanErrorIsFDAFixable)
        XCTAssertTrue(
            (state.cleanError ?? "").localizedCaseInsensitiveContains("skipped"),
            "The user must see the real reason, got: \(state.cleanError ?? "nil")"
        )
        XCTAssertTrue(fileManager.fileExists(atPath: folder.path))
    }

    // MARK: - Fixtures

    private func makeState() -> AppState {
        AppState(
            performStartupTasks: false,
            scanEngine: makeScanner(),
            cleaningEngine: makeCleaner(),
            historyStore: CleanupHistoryStore(
                fileURL: home.appendingPathComponent("history.json")
            )
        )
    }

    private func makeScanner() -> ScanEngine {
        ScanEngine(homeDirectory: home, tmpRoots: [], isAppRunning: { _ in false })
    }

    private func makeCleaner() -> CleaningEngine {
        CleaningEngine(homeDirectory: home, isAppRunning: { _ in false })
    }

    private func makeTranscript() throws -> String {
        let project = home.appendingPathComponent(
            ".claude/projects/-Users-test-demo",
            isDirectory: true
        )
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        let transcript = project.appendingPathComponent("77777777-7777-7777-7777-777777777777.jsonl")
        try Data(repeating: 0x42, count: 4096).write(to: transcript)
        // Old enough that the scan offers it as history.
        try fileManager.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: transcript.path
        )
        return transcript.path
    }

    private func waitForClean(_ state: AppState, timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !state.scanState.isActive { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Cleanup did not finish")
    }
}
