import Darwin
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

    func testIgnoredNodeModulesInARepositoryIsStillOffered() throws {
        let project = try makeProject("ignored-repo")
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data("node_modules/\n".utf8).write(to: project.appendingPathComponent(".gitignore"))
        try writeModules(in: project)
        try runGit(in: project, ["init", "-q"])

        XCTAssertEqual(offeredPaths(in: project), [canonical(modulesURL(in: project).path)])
    }

    func testUntrackedButNotIgnoredNodeModulesIsNotOffered() throws {
        let project = try makeProject("untracked-repo")
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try writeModules(in: project)
        try runGit(in: project, ["init", "-q"])

        XCTAssertTrue(offeredPaths(in: project).isEmpty, "the app rejects untracked-but-not-ignored folders")
    }

    func testOneTrackedFileDeepInsideAnIgnoredFolderBlocksIt() throws {
        let project = try makeProject("deep-tracked")
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try Data("node_modules/\n".utf8).write(to: project.appendingPathComponent(".gitignore"))
        try writeModules(in: project)
        try runGit(in: project, ["init", "-q"])
        try runGit(in: project, ["add", "-f", "node_modules/pkg/vendored.js"])

        XCTAssertTrue(offeredPaths(in: project).isEmpty)
    }

    func testNoRepositoryStillOffersTheArtifact() throws {
        let project = try makeProject("no-repo")
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))
        try writeModules(in: project)

        XCTAssertEqual(offeredPaths(in: project), [canonical(modulesURL(in: project).path)])
    }

    func testLinkedWorktreeUsesItsOwnGitFile() throws {
        let main = try makeProject("worktree-main")
        try Data("{}".utf8).write(to: main.appendingPathComponent("package.json"))
        try Data("node_modules/\n".utf8).write(to: main.appendingPathComponent(".gitignore"))
        try runGit(in: main, ["init", "-q"])
        try runGit(in: main, ["-c", "user.email=t@example.com", "-c", "user.name=Test", "commit", "--allow-empty", "-q", "-m", "init"])
        let worktree = root.appendingPathComponent("linked", isDirectory: true)
        try runGit(in: main, ["worktree", "add", "-q", worktree.path])
        try Data("{}".utf8).write(to: worktree.appendingPathComponent("package.json"))
        try Data("node_modules/\n".utf8).write(to: worktree.appendingPathComponent(".gitignore"))
        try writeModules(in: worktree)

        XCTAssertEqual(offeredPaths(in: worktree), [canonical(modulesURL(in: worktree).path)])

        try runGit(in: worktree, ["add", "-f", "node_modules/pkg/vendored.js"])
        XCTAssertTrue(offeredPaths(in: worktree).isEmpty, "a tracked file blocks it in a worktree too")
    }

    // MARK: - Fixtures

    private func makeProject(_ name: String) throws -> URL {
        let project = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        return project
    }

    private func modulesURL(in project: URL) -> URL {
        project.appendingPathComponent("node_modules", isDirectory: true)
    }

    private func writeModules(in project: URL) throws {
        let modules = modulesURL(in: project)
        try fileManager.createDirectory(
            at: modules.appendingPathComponent("pkg", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: 4_096)
            .write(to: modules.appendingPathComponent("pkg/vendored.js"))
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)],
            ofItemAtPath: modules.path
        )
    }

    private func canonical(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if realpath(path, &buffer) != nil { return String(cString: buffer) }
        return path
    }

    private func offeredPaths(in project: URL) -> [String] {
        let ignore = try? IgnoreStore(fileURL: root.appendingPathComponent("ignore"))
        guard let ignore else { return [] }
        return Purger.scan(roots: [project.path], olderThanDays: 0, ignore: ignore)
            .groups.flatMap(\.items).map(\.path)
    }

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