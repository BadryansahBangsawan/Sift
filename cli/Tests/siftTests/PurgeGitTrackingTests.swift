import Foundation
import XCTest
@testable import sift

/// `sift-cli purge` promises "project artifacts", not the user's repository
/// content. The app refuses a folder whose files git tracks; the CLI checks
/// only the project marker, so a committed vendor folder is offered and
/// `--force` would delete it permanently.
final class PurgeGitTrackingTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("sift-purge-git-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testGitTrackedNodeModulesIsNotOffered() throws {
        let project = root.appendingPathComponent("repo", isDirectory: true)
        let modules = project.appendingPathComponent("node_modules", isDirectory: true)
        try fileManager.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data(repeating: 0x41, count: 4_096)
            .write(to: modules.appendingPathComponent("vendored.js"))

        try runGit(in: project, ["init", "-q"])
        try runGit(in: project, ["add", "package.json", "node_modules"])
        let tracked = try gitOutput(in: project, ["ls-files"])
        XCTAssertTrue(tracked.contains("node_modules/vendored.js"), tracked)

        // Old enough for --force's age selection.
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)],
            ofItemAtPath: modules.path
        )

        let ignore = try IgnoreStore(fileURL: root.appendingPathComponent("ignore"))
        let scan = Purger.scan(roots: [project.path], olderThanDays: 0, ignore: ignore)

        XCTAssertTrue(
            scan.groups.flatMap(\.items).isEmpty,
            "a node_modules whose files git tracks is repository content, not build output"
        )
    }

    // MARK: - Git fixture

    private func runGit(in directory: URL, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw XCTSkip("git is not available in this environment")
        }
    }

    private func gitOutput(in directory: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw XCTSkip("git is not available in this environment")
        }
        return String(decoding: data, as: UTF8.self)
    }
}