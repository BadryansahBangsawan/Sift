import XCTest
@testable import Sift

final class UninstallPlanTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UninstallPlanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPlanListsEachFileWithItsGroupSizeAndTheTotal() {
        let app = URL(fileURLWithPath: "/Applications/Editor.app")
        let cache = URL(fileURLWithPath: "/Users/me/Library/Caches/com.example.editor")
        let prefs = URL(fileURLWithPath: "/Users/me/Library/Preferences/com.example.editor.plist")
        let sizes: [URL: Int64] = [app: 1_000, cache: 250, prefs: 4]

        let plan = UninstallPlan(files: [prefs, cache, app]) { sizes[$0] }

        XCTAssertEqual(plan.entries, [
            UninstallPlan.Entry(url: app, group: .application, size: 1_000),
            UninstallPlan.Entry(url: cache, group: .caches, size: 250),
            UninstallPlan.Entry(url: prefs, group: .preferences, size: 4),
        ])
        XCTAssertEqual(plan.totalSize, 1_254)
    }

    func testUnreadableFileCountsAsZeroBytes() {
        let missing = URL(fileURLWithPath: "/Users/me/Library/Logs/gone.log")

        let plan = UninstallPlan(files: [missing]) { _ in nil }

        XCTAssertEqual(plan.entries, [UninstallPlan.Entry(url: missing, group: .logs, size: 0)])
        XCTAssertEqual(plan.totalSize, 0)
    }

    func testProducingAPlanLeavesTheFilesUntouched() throws {
        let fm = FileManager.default
        let appURL = tempDir.appendingPathComponent("Editor.app")
        let binary = appURL.appendingPathComponent("Contents/MacOS/Editor")
        let cacheFile = tempDir.appendingPathComponent("Library/Caches/com.example.editor/cache.db")
        for file in [binary, cacheFile] {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: 10_000).write(to: file)
        }
        let cacheDir = cacheFile.deletingLastPathComponent()
        let watched = [appURL, binary, cacheDir, cacheFile]
        let before = try watched.map { try snapshot(of: $0) }

        let plan = UninstallPlan(files: [appURL, cacheDir])

        XCTAssertEqual(try watched.map { try snapshot(of: $0) }, before)
        XCTAssertEqual(plan.entries.map(\.group), [.application, .caches])
        XCTAssertTrue(plan.entries.allSatisfy { $0.size >= 10_000 })
    }

    /// Existence, contents (for files) and modification date.
    private func snapshot(of url: URL) throws -> [String] {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        let isFile = (attrs[.type] as? FileAttributeType) == .typeRegular
        let contents = isFile ? try Data(contentsOf: url).base64EncodedString() : "dir"
        return [url.path, "\(modified)", contents]
    }
}
