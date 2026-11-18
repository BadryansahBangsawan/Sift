import XCTest
@testable import Sift

/// Project junk must offer only folders it can prove are generated output.
/// Every test builds real folders (and real git repositories) in a temporary
/// directory; nothing outside it is read or changed.
final class ProjectJunkTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("sift-project-junk-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        // Scan roots are compared after symlink resolution (/var -> /private/var).
        root = root.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
    }

    // MARK: - Accepted

    func testAcceptsInstalledNodeModulesThatGitIgnores() throws {
        let app = try project("web", files: ["package.json": "{}", ".gitignore": "node_modules/\n"])
        try gitCommitAll(app)
        let modules = try npmModules(in: app)

        let evaluation = finder().evaluate(modules, roots: [root])

        guard case .accepted(let kind, let project, let evidence, let git) = evaluation else {
            return XCTFail("expected accepted, got \(evaluation)")
        }
        XCTAssertEqual(kind, "node_modules")
        XCTAssertEqual(project.path, app.path)
        XCTAssertTrue(evidence.contains("package.json"))
        XCTAssertTrue(evidence.contains(".package-lock.json"))
        XCTAssertEqual(git, .ignored)
    }

    func testAcceptsCargoTargetOutsideGitWithCacheDirTag() throws {
        let crate = try project("crate", files: ["Cargo.toml": "[package]\n"])
        let target = try folder(crate, "target", files: ["CACHEDIR.TAG": "Signature: 8a477f597d28d172789f06886806bc55", "debug/app": "bin"])

        let evaluation = finder().evaluate(target, roots: [root])

        guard case .accepted(_, _, let evidence, let git) = evaluation else {
            return XCTFail("expected accepted, got \(evaluation)")
        }
        XCTAssertTrue(evidence.contains("Cargo.toml"))
        XCTAssertTrue(evidence.contains("CACHEDIR.TAG"))
        XCTAssertEqual(git, .noRepository)
    }

    func testAcceptsPythonVirtualEnvironment() throws {
        let tool = try project("tool", files: ["pyproject.toml": ""])
        let venv = try folder(tool, ".venv", files: ["pyvenv.cfg": "home = /usr/bin", "bin/python": ""])

        XCTAssertTrue(finder().evaluate(venv, roots: [root]).isAccepted)
    }

    // MARK: - Rejected: not provably generated

    func testRejectsNodeModulesWithoutPackageJSON() throws {
        let loose = try project("loose", files: ["README.md": ""])
        let modules = try npmModules(in: loose)

        XCTAssertEqual(finder().evaluate(modules, roots: [root]), .rejected(.missingProjectMarker))
    }

    func testRejectsNodeModulesWithoutInstallSignature() throws {
        let app = try project("handmade", files: ["package.json": "{}"])
        let modules = try folder(app, "node_modules", files: ["notes.txt": "my own files"])

        XCTAssertEqual(finder().evaluate(modules, roots: [root]), .rejected(.missingContentSignature))
    }

    func testRejectsCargoTargetWithoutBuildSignature() throws {
        let crate = try project("crate", files: ["Cargo.toml": "[package]\n"])
        let target = try folder(crate, "target", files: ["deploy.md": "hand-written"])

        XCTAssertEqual(finder().evaluate(target, roots: [root]), .rejected(.missingContentSignature))
    }

    func testRejectsPycacheThatHoldsSourceFiles() throws {
        let pkg = try project("pkg", files: ["setup.py": ""])
        let cache = try folder(pkg, "__pycache__", files: ["mod.cpython-312.pyc": "x", "keep.py": "print(1)"])

        XCTAssertEqual(finder().evaluate(cache, roots: [root]), .rejected(.missingContentSignature))
    }

    func testRejectsFolderNamesThatOftenHoldSource() throws {
        let app = try project("site", files: ["package.json": "{}"])
        for name in ["dist", "build", "out", "src", "lib", "vendor", "bin", "public"] {
            let candidate = try folder(app, name, files: ["index.js": ""])
            XCTAssertEqual(finder().evaluate(candidate, roots: [root]), .rejected(.notAnArtifact), name)
        }
    }

    // MARK: - Rejected: git says it is part of the project

    func testRejectsNodeModulesCommittedToGit() throws {
        let app = try project("vendored", files: ["package.json": "{}"])
        let modules = try npmModules(in: app)
        try gitCommitAll(app)

        XCTAssertEqual(finder().evaluate(modules, roots: [root]), .rejected(.trackedByGit))
    }

    func testRejectsArtifactThatGitDoesNotIgnore() throws {
        let app = try project("unignored", files: ["package.json": "{}"])
        try gitCommitAll(app)
        let modules = try npmModules(in: app)

        XCTAssertEqual(finder().evaluate(modules, roots: [root]), .rejected(.notIgnoredByGit))
    }

    func testRejectsArtifactInRepositoryWhenGitCannotAnswer() throws {
        let app = try project("nogit", files: ["package.json": "{}", ".gitignore": "node_modules/\n"])
        try gitCommitAll(app)
        let modules = try npmModules(in: app)

        let blind = ProjectJunkFinder(git: UnavailableGit(), excludedPaths: [])
        XCTAssertEqual(blind.evaluate(modules, roots: [root]), .rejected(.gitUnavailable))
    }

    // MARK: - Rejected: structure

    func testRejectsArtifactThatContainsARepository() throws {
        let app = try project("nested", files: ["package.json": "{}"])
        let modules = try npmModules(in: app)
        try fileManager.createDirectory(at: modules.appendingPathComponent(".git"), withIntermediateDirectories: true)

        XCTAssertEqual(finder().evaluate(modules, roots: [root]), .rejected(.containsRepository))
    }

    func testRejectsSymlinkedArtifact() throws {
        let app = try project("linked", files: ["package.json": "{}"])
        let elsewhere = try project("elsewhere", files: [:])
        let real = try npmModules(in: elsewhere)
        let link = app.appendingPathComponent("node_modules")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)

        XCTAssertEqual(finder().evaluate(link, roots: [root]), .rejected(.symlink))
    }

    func testRejectsArtifactReachedThroughSymlinkedFolder() throws {
        let real = try project("real", files: ["package.json": "{}"])
        _ = try npmModules(in: real)
        let alias = root.appendingPathComponent("alias")
        try fileManager.createSymbolicLink(at: alias, withDestinationURL: real)

        let throughAlias = alias.appendingPathComponent("node_modules")
        XCTAssertEqual(finder().evaluate(throughAlias, roots: [root]), .rejected(.symlink))
    }

    func testRejectsArtifactInsideAnotherArtifact() throws {
        let app = try project("outer", files: ["package.json": "{}"])
        let modules = try npmModules(in: app)
        let inner = modules.appendingPathComponent("left-pad")
        let innerModules = try npmModules(in: inner)

        XCTAssertEqual(finder().evaluate(innerModules, roots: [root]), .rejected(.insideAnotherArtifact))
    }

    func testRejectsArtifactsInsideHiddenToolFolders() throws {
        // Agent worktrees and tool caches live in hidden folders and may be in use.
        let worktree = try project("app/.claude/worktrees/agent-1", files: ["package.json": "{}"])
        let modules = try npmModules(in: worktree)

        XCTAssertEqual(finder().evaluate(modules, roots: [root]), .rejected(.insideHiddenFolder))
    }

    func testRejectsScanRootAndPathsOutsideIt() throws {
        let app = try project("app", files: ["package.json": "{}"])
        let modules = try npmModules(in: app)

        XCTAssertEqual(finder().evaluate(modules, roots: [modules]), .rejected(.scanRoot))
        let other = try project("other", files: [:])
        XCTAssertEqual(finder().evaluate(modules, roots: [other]), .rejected(.outsideProjectFolders))
    }

    func testRejectsPathsTheUserExcluded() throws {
        let app = try project("keep", files: ["package.json": "{}"])
        let modules = try npmModules(in: app)

        let finder = ProjectJunkFinder(git: GitCommandLine(homeDirectory: root), excludedPaths: [app.path])
        XCTAssertEqual(finder.evaluate(modules, roots: [root]), .rejected(.excludedByUser))
    }

    // MARK: - Scan

    func testScanOffersOnlyProvableJunkAndExplainsEverySkip() async throws {
        let web = try project("web", files: ["package.json": "{}", ".gitignore": "node_modules/\n"])
        try gitCommitAll(web)
        let webModules = try npmModules(in: web)
        _ = try npmModules(in: webModules.appendingPathComponent("left-pad")) // nested: never listed
        let crate = try project("crate", files: ["Cargo.toml": ""])
        let target = try folder(crate, "target", files: ["CACHEDIR.TAG": "Signature", "debug/app": String(repeating: "x", count: 8192)])
        let docs = try project("docs", files: ["Cargo.toml": ""])
        let handTarget = try folder(docs, "target", files: ["notes.md": "mine"])
        _ = try folder(web, "dist", files: ["app.js": ""])

        let result = try await finder().scan(roots: [root]) { _ in }

        XCTAssertEqual(Set(result.artifacts.map(\.url.path)), [webModules.path, target.path])
        XCTAssertEqual(result.skipped.map(\.url.path), [handTarget.path])
        XCTAssertEqual(result.skipped.first?.reason, .missingContentSignature)
        XCTAssertTrue(result.artifacts.allSatisfy { $0.size > 0 })
    }

    // MARK: - Move to Trash

    func testMoveToTrashChecksEveryFolderAgain() async throws {
        let app = try project("app", files: ["package.json": "{}"])
        let modules = try npmModules(in: app)
        let result = try await finder().scan(roots: [root]) { _ in }
        XCTAssertEqual(result.artifacts.map(\.url.path), [modules.path])

        try fileManager.removeItem(at: app.appendingPathComponent("package.json"))
        var trashed: [URL] = []
        let report = finder().moveToTrash(result.artifacts, roots: [root]) { trashed.append($0) }

        XCTAssertTrue(trashed.isEmpty)
        XCTAssertTrue(report.moved.isEmpty)
        XCTAssertEqual(report.failures.map(\.reason), [.missingProjectMarker])
    }

    func testMoveToTrashUsesTheTrashForAcceptedFolders() async throws {
        let app = try project("app", files: ["package.json": "{}"])
        let modules = try npmModules(in: app)
        let result = try await finder().scan(roots: [root]) { _ in }

        var trashed: [URL] = []
        let report = finder().moveToTrash(result.artifacts, roots: [root]) { trashed.append($0) }

        XCTAssertEqual(trashed.map(\.path), [modules.path])
        XCTAssertEqual(report.moved.map(\.url.path), [modules.path])
        XCTAssertTrue(report.failures.isEmpty)
    }

    // MARK: - Project folders

    func testProjectFoldersDefaultToExistingCandidatesAndCollapseNesting() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "sift-project-folders-\(UUID().uuidString)"))
        let home = try project("home", files: [:])
        try fileManager.createDirectory(at: home.appendingPathComponent("Code/app"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: home.appendingPathComponent("Developer"), withIntermediateDirectories: true)

        XCTAssertEqual(ProjectFolders.load(defaults: defaults, home: home).map(\.lastPathComponent), ["Code", "Developer"])

        ProjectFolders.save([home.appendingPathComponent("Code/app"), home.appendingPathComponent("Code"), URL(fileURLWithPath: "/")], defaults: defaults)
        XCTAssertEqual(ProjectFolders.load(defaults: defaults, home: home).map(\.path), [home.appendingPathComponent("Code").path])
    }

    // MARK: - Fixtures

    private func finder() -> ProjectJunkFinder {
        ProjectJunkFinder(git: GitCommandLine(homeDirectory: root), excludedPaths: [])
    }

    private func project(_ name: String, files: [String: String]) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try write(files, into: url)
        return url
    }

    private func folder(_ parent: URL, _ name: String, files: [String: String]) throws -> URL {
        let url = parent.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try write(files, into: url)
        return url
    }

    /// A node_modules folder as npm leaves it.
    private func npmModules(in parent: URL) throws -> URL {
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        return try folder(parent, "node_modules", files: [
            ".package-lock.json": "{}",
            "left-pad/package.json": "{\"name\":\"left-pad\"}",
            "left-pad/index.js": String(repeating: "x", count: 8192),
        ])
    }

    private func write(_ files: [String: String], into directory: URL) throws {
        for (path, contents) in files {
            let url = directory.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
    }

    private func gitCommitAll(_ repository: URL) throws {
        try git(["init", "-q"], in: repository)
        try git(["add", "-A"], in: repository)
        try git(["-c", "user.name=Sift Tests", "-c", "user.email=tests@sift.invalid",
                 "commit", "-q", "--no-gpg-sign", "-m", "fixture"], in: repository)
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = try XCTUnwrap(GitCommandLine.locateExecutable())
        process.arguments = ["-C", directory.path] + arguments
        process.environment = ["HOME": root.path, "GIT_CONFIG_NOSYSTEM": "1"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " "))")
    }
}

private struct UnavailableGit: ProjectGitInspecting {
    func status(ofItemAt relativePath: String, inRepository repository: URL) -> ProjectGitStatus { .unavailable }
}

private extension ProjectArtifactEvaluation {
    var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
}
