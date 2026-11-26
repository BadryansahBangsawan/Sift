import Darwin
import Foundation

// Project junk: dependency folders and build output inside the user's project
// folders (node_modules, .venv, target, .build, ...).
//
// The one rule: offer a folder only when Sift can prove it is generated
// output. Missing some junk is acceptable; offering a folder that holds code
// or committed files is not. Every check runs at scan time AND again right
// before a folder is moved, and folders go to the Trash, never unlinked.
//
// The artifact names match `cli/Sources/sift/Core/Purger.swift`; the app adds
// the parent-marker, content-signature and git checks on top.

/// A generated folder Sift can offer for removal.
struct ProjectArtifact: Identifiable, Hashable, Sendable {
    let url: URL
    let project: URL
    /// The folder's name, e.g. `node_modules`.
    let kind: String
    /// File names that proved the folder is generated, e.g. `package.json`.
    let evidence: [String]
    let git: ProjectArtifactGitState
    /// Bytes freed when the folder is deleted (hard-linked files excluded).
    let size: Int64
    let modifiedAt: Date?

    var id: URL { url }
}

enum ProjectArtifactGitState: Equatable, Sendable {
    /// Inside a git work tree, untracked and ignored.
    case ignored
    /// Not inside any git work tree.
    case noRepository
}

enum ProjectArtifactRejection: Equatable, Sendable {
    case notAnArtifact
    case outsideProjectFolders
    case scanRoot
    case excludedByUser
    case symlink
    case notADirectory
    case insideAnotherArtifact
    case insideHiddenFolder
    case cloudPlaceholder
    case containsRepository
    case missingProjectMarker
    case missingContentSignature
    case trackedByGit
    case notIgnoredByGit
    case gitUnavailable

    var message: String {
        switch self {
        case .notAnArtifact: return String(localized: "Not a known build or dependency folder")
        case .outsideProjectFolders: return String(localized: "Outside your project folders")
        case .scanRoot: return String(localized: "This is one of your project folders")
        case .excludedByUser: return String(localized: "Excluded in Settings")
        case .symlink: return String(localized: "Reached through a symbolic link")
        case .notADirectory: return String(localized: "Not a folder")
        case .insideAnotherArtifact: return String(localized: "Inside another dependency folder")
        case .insideHiddenFolder: return String(localized: "Inside a hidden folder that a tool manages")
        case .cloudPlaceholder: return String(localized: "Stored in iCloud, not on this Mac")
        case .containsRepository: return String(localized: "Contains a git repository")
        case .missingProjectMarker: return String(localized: "No matching project file next to it")
        case .missingContentSignature: return String(localized: "Its contents don't look generated")
        case .trackedByGit: return String(localized: "Git tracks files inside it")
        case .notIgnoredByGit: return String(localized: "Git does not ignore it")
        case .gitUnavailable: return String(localized: "Git could not confirm it is ignored")
        }
    }
}

enum ProjectArtifactEvaluation: Equatable, Sendable {
    case accepted(kind: String, project: URL, evidence: [String], git: ProjectArtifactGitState)
    case rejected(ProjectArtifactRejection)
}

struct ProjectArtifactSkip: Identifiable, Hashable, Sendable {
    let url: URL
    let reason: ProjectArtifactRejection
    var id: URL { url }
}

struct ProjectJunkScanResult: Sendable {
    let roots: [URL]
    let artifacts: [ProjectArtifact]
    /// Folders with an artifact name that failed a check, with the reason.
    let skipped: [ProjectArtifactSkip]

    var totalSize: Int64 { artifacts.reduce(0) { $0 + $1.size } }
}

struct ProjectJunkScanProgress: Sendable {
    var foldersVisited: Int
    var candidatesChecked: Int
    var candidatesTotal: Int
    var currentURL: URL?
}

struct ProjectJunkTrashReport: Sendable {
    struct Failure: Sendable {
        let url: URL
        let reason: ProjectArtifactRejection?
        let message: String
    }

    var moved: [ProjectArtifact] = []
    var failures: [Failure] = []
}

// MARK: - Git

enum ProjectGitStatus: Equatable, Sendable {
    case ignoredAndUntracked
    case tracked
    case notIgnored
    case unavailable
}

protocol ProjectGitInspecting: Sendable {
    /// Whether git tracks anything under `relativePath` and whether it ignores it.
    func status(ofItemAt relativePath: String, inRepository repository: URL) -> ProjectGitStatus
}

/// Asks the git command-line tool. Never uses `/usr/bin/git` directly: on a Mac
/// without developer tools that stub opens an install prompt.
struct GitCommandLine: ProjectGitInspecting {
    /// Overrides HOME (and skips the system config) so tests don't read the
    /// machine's global ignore rules.
    var homeDirectory: URL?
    var timeout: TimeInterval = 15

    func status(ofItemAt relativePath: String, inRepository repository: URL) -> ProjectGitStatus {
        guard let executable = Self.locateExecutable(), !relativePath.isEmpty else { return .unavailable }
        guard let tracked = run(executable, Self.safeOptions + ["-C", repository.path, "ls-files", "-z", "--", relativePath]),
              tracked.status == 0 else { return .unavailable }
        if !tracked.output.isEmpty { return .tracked }
        guard let ignored = run(executable, Self.safeOptions + ["-C", repository.path, "check-ignore", "-q", "--", relativePath]) else {
            return .unavailable
        }
        switch ignored.status {
        case 0: return .ignoredAndUntracked
        case 1: return .notIgnored
        default: return .unavailable
        }
    }

    /// A repository's own .git/config (for example from a downloaded archive)
    /// can name an fsmonitor program that git runs whenever it reads the index.
    /// Command-line settings beat every config file, so scanning never runs it.
    static let safeOptions = ["-c", "core.fsmonitor=false"]

    static func locateExecutable(fileManager: FileManager = .default) -> URL? {
        var candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git"]
        if let developer = developerDirectory() {
            candidates.append(developer + "/usr/bin/git")
        }
        candidates.append("/Library/Developer/CommandLineTools/usr/bin/git")
        return candidates.lazy
            .filter { fileManager.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
            .first
    }

    /// `xcode-select -p` reports the active developer directory without
    /// prompting to install anything.
    private static func developerDirectory() -> String? {
        let result = ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/xcode-select"),
            arguments: ["-p"],
            timeout: 5
        )
        guard !result.timedOut, result.status == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }
    private func run(_ executable: URL, _ arguments: [String]) -> (status: Int32, output: Data)? {
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        if let homeDirectory {
            environment["HOME"] = homeDirectory.path
            environment["XDG_CONFIG_HOME"] = homeDirectory.appendingPathComponent(".config").path
            environment["GIT_CONFIG_NOSYSTEM"] = "1"
        }
        let result = ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            environment: environment
        )
        guard !result.timedOut else { return nil }
        return (result.status, Data(result.stdout.utf8))
    }}

// MARK: - Rules

private struct ArtifactRule {
    /// Any one of these must sit next to the folder. Empty: the folder proves itself.
    /// A leading `*` matches by suffix (`*.xcodeproj`).
    let markers: [String]
    /// Returns the evidence that the contents are generated, or nil.
    let signature: (URL, FileManager) -> [String]?
}

private enum ArtifactRules {
    static let names: Set<String> = [
        "node_modules", ".next", ".nuxt", ".turbo", ".svelte-kit", ".angular", ".parcel-cache",
        "target", ".build", "DerivedData", "Pods",
        ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".tox", ".ruff_cache",
        ".gradle",
    ]
    static let prefixes = ["cmake-build"]

    static func isArtifactName(_ name: String) -> Bool {
        names.contains(name) || prefixes.contains { name.hasPrefix($0) }
    }

    static func rule(for name: String) -> ArtifactRule? {
        if name.hasPrefix("cmake-build") {
            return ArtifactRule(markers: ["CMakeLists.txt"], signature: anyOf(["CMakeCache.txt"]))
        }
        switch name {
        case "node_modules":
            return ArtifactRule(markers: ["package.json"], signature: nodeModulesSignature)
        case ".next":
            return ArtifactRule(markers: ["package.json"], signature: anyOf(["BUILD_ID", "cache"]))
        case ".nuxt", ".turbo", ".svelte-kit", ".angular", ".parcel-cache":
            return ArtifactRule(markers: ["package.json"], signature: nonEmpty)
        case "target":
            return ArtifactRule(
                markers: ["Cargo.toml", "pom.xml", "build.sbt"],
                signature: anyOf(["CACHEDIR.TAG", ".rustc_info.json", "classes", "maven-status", "maven-archiver", "streams"])
            )
        case ".build":
            return ArtifactRule(markers: ["Package.swift"], signature: anyOf(["workspace-state.json", "debug.yaml", "release.yaml", ".lock"]))
        case "DerivedData":
            return ArtifactRule(markers: ["*.xcodeproj", "*.xcworkspace"], signature: derivedDataSignature)
        case "Pods":
            return ArtifactRule(markers: ["Podfile"], signature: anyOf(["Manifest.lock"]))
        case ".gradle":
            return ArtifactRule(
                markers: ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
                signature: gradleSignature
            )
        case ".venv", "venv":
            return ArtifactRule(markers: [], signature: anyOf(["pyvenv.cfg"]))
        case "__pycache__":
            return ArtifactRule(markers: [], signature: bytecodeOnly)
        case ".pytest_cache", ".mypy_cache", ".ruff_cache":
            return ArtifactRule(markers: [], signature: anyOf(["CACHEDIR.TAG"]))
        case ".tox":
            return ArtifactRule(markers: ["tox.ini", "pyproject.toml", "setup.cfg", "setup.py"], signature: toxSignature)
        default:
            return nil
        }
    }

    static func anyOf(_ entries: [String]) -> (URL, FileManager) -> [String]? {
        { folder, _ in
            entries.first { lexists(folder.appendingPathComponent($0)) }.map { [$0] }
        }
    }

    static func nonEmpty(_ folder: URL, _ fileManager: FileManager) -> [String]? {
        let entries = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return entries.isEmpty ? nil : []
    }

    /// npm, pnpm, Yarn and Bun leave a state file, or at least installed packages.
    static func nodeModulesSignature(_ folder: URL, _ fileManager: FileManager) -> [String]? {
        for state in [".package-lock.json", ".modules.yaml", ".yarn-state.yml", ".yarn-integrity"]
        where lexists(folder.appendingPathComponent(state)) {
            return [state]
        }
        let children = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().prefix(500)
        for child in children where !child.hasPrefix(".") {
            let childURL = folder.appendingPathComponent(child)
            if child.hasPrefix("@") {
                let scoped = ((try? fileManager.contentsOfDirectory(atPath: childURL.path)) ?? []).sorted().prefix(50)
                if let package = scoped.first(where: { isRegularFile(childURL.appendingPathComponent($0).appendingPathComponent("package.json")) }) {
                    return ["\(child)/\(package)/package.json"]
                }
            } else if isRegularFile(childURL.appendingPathComponent("package.json")) {
                return ["\(child)/package.json"]
            }
        }
        return nil
    }

    static func derivedDataSignature(_ folder: URL, _ fileManager: FileManager) -> [String]? {
        if let direct = anyOf(["Build", "Index.noindex", "ModuleCache.noindex", "info.plist"])(folder, fileManager) {
            return direct
        }
        let children = ((try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().prefix(200)
        return children.first { lexists(folder.appendingPathComponent($0).appendingPathComponent("info.plist")) }
            .map { ["\($0)/info.plist"] }
    }

    static func gradleSignature(_ folder: URL, _ fileManager: FileManager) -> [String]? {
        if lexists(folder.appendingPathComponent("buildOutputCleanup")) { return ["buildOutputCleanup"] }
        let children = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return children.first { name in
            let parts = name.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        }.map { [$0] }
    }

    /// Only compiled bytecode, no subfolders, no source.
    static func bytecodeOnly(_ folder: URL, _ fileManager: FileManager) -> [String]? {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: folder.path), !entries.isEmpty else { return nil }
        for entry in entries {
            guard isRegularFile(folder.appendingPathComponent(entry)),
                  entry.hasSuffix(".pyc") || entry.hasSuffix(".pyo") else { return nil }
        }
        return ["*.pyc"]
    }

    static func toxSignature(_ folder: URL, _ fileManager: FileManager) -> [String]? {
        let children = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return children.sorted().first { child in
            lexists(folder.appendingPathComponent(child).appendingPathComponent("pyvenv.cfg"))
                || lexists(folder.appendingPathComponent(child).appendingPathComponent(".tox-info.json"))
        }.map { ["\($0)/pyvenv.cfg"] }
    }

    static func lexists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }
}

// MARK: - Finder

struct ProjectJunkFinder: Sendable {
    let git: ProjectGitInspecting
    let excludedPaths: [String]
    let cleanupLog: CleanupLog
    /// Deepest folder level below a project folder that is searched.
    var maxDepth = 8

    init(
        git: ProjectGitInspecting = GitCommandLine(),
        excludedPaths: [String] = CleanupExclusions.paths(),
        cleanupLog: CleanupLog = .shared
    ) {
        self.git = git
        self.excludedPaths = excludedPaths
        self.cleanupLog = cleanupLog
    }

    /// The single decision point, used by the scan and again before moving.
    func evaluate(_ candidate: URL, roots: [URL]) -> ProjectArtifactEvaluation {
        let fileManager = FileManager()
        let url = candidate.standardizedFileURL
        let name = url.lastPathComponent
        guard ArtifactRules.isArtifactName(name), let rule = ArtifactRules.rule(for: name) else {
            return .rejected(.notAnArtifact)
        }

        let normalizedRoots = ProjectFolders.normalized(roots)
        if normalizedRoots.contains(where: { $0.path == url.path }) { return .rejected(.scanRoot) }
        guard let root = normalizedRoots.first(where: { url.path.hasPrefix($0.path + "/") }) else {
            return .rejected(.outsideProjectFolders)
        }
        if CleanupExclusions.excludes(url.path, paths: excludedPaths) { return .rejected(.excludedByUser) }

        // No symbolic link anywhere between the project folder and the candidate.
        let components = url.path.dropFirst(root.path.count + 1).split(separator: "/").map(String.init)
        var walk = root
        for (index, component) in components.enumerated() {
            walk.appendPathComponent(component)
            var info = stat()
            guard lstat(walk.path, &info) == 0 else { return .rejected(.notADirectory) }
            if (info.st_mode & S_IFMT) == S_IFLNK { return .rejected(.symlink) }
            guard (info.st_mode & S_IFMT) == S_IFDIR else { return .rejected(.notADirectory) }
            let isCandidate = index == components.count - 1
            if !isCandidate, ArtifactRules.isArtifactName(component) { return .rejected(.insideAnotherArtifact) }
            // Hidden folders (.claude/worktrees, .worktrees, .open-next, ...) belong
            // to tools and agents that may be using them right now.
            if !isCandidate, component.hasPrefix(".") { return .rejected(.insideHiddenFolder) }
            if isCandidate, info.st_flags & UInt32(SF_DATALESS) != 0 { return .rejected(.cloudPlaceholder) }
        }

        if ArtifactRules.lexists(url.appendingPathComponent(".git")) { return .rejected(.containsRepository) }

        let project = url.deletingLastPathComponent()
        var evidence: [String] = []
        if !rule.markers.isEmpty {
            guard let marker = Self.marker(rule.markers, in: project, fileManager: fileManager) else {
                return .rejected(.missingProjectMarker)
            }
            evidence.append(marker)
        }
        guard let signature = rule.signature(url, fileManager) else { return .rejected(.missingContentSignature) }
        evidence.append(contentsOf: signature)

        guard let repository = Self.repository(containing: project) else {
            return .accepted(kind: name, project: project, evidence: evidence, git: .noRepository)
        }
        let relative = String(url.path.dropFirst(repository.path.count + 1))
        switch git.status(ofItemAt: relative, inRepository: repository) {
        case .ignoredAndUntracked:
            return .accepted(kind: name, project: project, evidence: evidence, git: .ignored)
        case .tracked: return .rejected(.trackedByGit)
        case .notIgnored: return .rejected(.notIgnoredByGit)
        case .unavailable: return .rejected(.gitUnavailable)
        }
    }

    func scan(
        roots: [URL],
        progress: @escaping @Sendable (ProjectJunkScanProgress) async -> Void
    ) async throws -> ProjectJunkScanResult {
        let normalizedRoots = ProjectFolders.normalized(roots)
        var candidates: [URL] = []
        var visited = 0
        for root in normalizedRoots {
            try Task.checkCancellation()
            guard let enumerator = FileManager().enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                visited += 1
                if visited % 500 == 0 {
                    try Task.checkCancellation()
                    await progress(ProjectJunkScanProgress(foldersVisited: visited, candidatesChecked: 0, candidatesTotal: candidates.count, currentURL: url))
                }
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                guard values?.isDirectory == true else { continue }
                let name = url.lastPathComponent
                if name == ".git" || name == ".Trash" || name == ".Trashes" { enumerator.skipDescendants(); continue }
                if ArtifactRules.isArtifactName(name) {
                    enumerator.skipDescendants()
                    candidates.append(url.standardizedFileURL)
                    continue
                }
                if enumerator.level >= maxDepth { enumerator.skipDescendants() }
            }
        }

        var artifacts: [ProjectArtifact] = []
        var skipped: [ProjectArtifactSkip] = []
        var accepted: [(url: URL, kind: String, project: URL, evidence: [String], git: ProjectArtifactGitState)] = []
        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress(ProjectJunkScanProgress(foldersVisited: visited, candidatesChecked: index, candidatesTotal: candidates.count, currentURL: candidate))
            switch evaluate(candidate, roots: normalizedRoots) {
            case .accepted(let kind, let project, let evidence, let git):
                accepted.append((candidate, kind, project, evidence, git))
            case .rejected(let reason):
                skipped.append(ProjectArtifactSkip(url: candidate, reason: reason))
            }
        }

        // Size the accepted folders a few at a time.
        let acceptedURLs = accepted.map(\.url)
        let sized = try await withThrowingTaskGroup(of: (Int, Int64, Date?).self) { group in
            var results: [(Int, Int64, Date?)] = []
            var next = 0
            while next < min(4, acceptedURLs.count) {
                let index = next, url = acceptedURLs[index]
                group.addTask {
                    try Task.checkCancellation()
                    return (index, Self.reclaimableSize(of: url), Self.modificationDate(of: url))
                }
                next += 1
            }
            while let result = try await group.next() {
                results.append(result)
                await progress(ProjectJunkScanProgress(
                    foldersVisited: visited, candidatesChecked: candidates.count,
                    candidatesTotal: candidates.count, currentURL: acceptedURLs[result.0]
                ))
                if next < acceptedURLs.count {
                    let index = next, url = acceptedURLs[index]
                    group.addTask {
                        try Task.checkCancellation()
                        return (index, Self.reclaimableSize(of: url), Self.modificationDate(of: url))
                    }
                    next += 1
                }
            }
            return results
        }
        for (index, size, modified) in sized where size > 0 {
            let item = accepted[index]
            artifacts.append(ProjectArtifact(
                url: item.url, project: item.project, kind: item.kind, evidence: item.evidence,
                git: item.git, size: size, modifiedAt: modified
            ))
        }
        artifacts.sort { $0.size == $1.size ? $0.url.path < $1.url.path : $0.size > $1.size }
        skipped.sort { $0.url.path < $1.url.path }
        return ProjectJunkScanResult(roots: normalizedRoots, artifacts: artifacts, skipped: skipped)
    }

    /// Re-checks every folder, then moves the ones that still qualify to the Trash.
    func moveToTrash(
        _ artifacts: [ProjectArtifact],
        roots: [URL],
        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> ProjectJunkTrashReport {
        var report = ProjectJunkTrashReport()
        for artifact in artifacts {
            switch evaluate(artifact.url, roots: roots) {
            case .accepted:
                do {
                    try trash(artifact.url)
                    report.moved.append(artifact)
                    cleanupLog.record(
                        source: "projectJunk",
                        category: artifact.kind,
                        action: .trashed,
                        path: artifact.url.path,
                        bytes: artifact.size
                    )
                } catch {
                    report.failures.append(.init(url: artifact.url, reason: nil, message: error.localizedDescription))
                    cleanupLog.record(
                        source: "projectJunk",
                        category: artifact.kind,
                        action: .failed,
                        path: artifact.url.path,
                        bytes: artifact.size,
                        reason: error.localizedDescription
                    )
                }
            case .rejected(let reason):
                report.failures.append(.init(url: artifact.url, reason: reason, message: reason.message))
                cleanupLog.record(
                    source: "projectJunk",
                    category: artifact.kind,
                    action: .skipped,
                    path: artifact.url.path,
                    bytes: artifact.size,
                    reason: reason.message
                )
            }
        }
        return report
    }

    // MARK: Helpers

    private static func marker(_ markers: [String], in project: URL, fileManager: FileManager) -> String? {
        for marker in markers where !marker.hasPrefix("*") {
            if ArtifactRules.lexists(project.appendingPathComponent(marker)) { return marker }
        }
        let suffixes = markers.filter { $0.hasPrefix("*") }.map { String($0.dropFirst()) }
        guard !suffixes.isEmpty else { return nil }
        let entries = (try? fileManager.contentsOfDirectory(atPath: project.path)) ?? []
        return entries.sorted().first { entry in suffixes.contains { entry.hasSuffix($0) } }
    }

    /// The nearest folder at or above `folder` holding a `.git` directory or file.
    private static func repository(containing folder: URL) -> URL? {
        var path = folder.standardizedFileURL.path
        while path.hasPrefix("/") {
            let current = URL(fileURLWithPath: path, isDirectory: true)
            if ArtifactRules.lexists(current.appendingPathComponent(".git")) { return current }
            if path == "/" { return nil }
            path = (path as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Allocated bytes of files with a single link. Hard-linked files (pnpm's
    /// store, for example) stay on disk after the folder is removed, so they
    /// are not counted as space you get back.
    static func reclaimableSize(of folder: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .linkCountKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager().enumerator(at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) else {
            return 0
        }
        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            if let links = values.linkCount, links > 1 { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

// MARK: - Project folders

/// The folders Sift searches for project junk.
enum ProjectFolders {
    static let defaultsKey = "Sift.ProjectFolders"
    static let defaultNames = ["Projects", "Code", "dev", "Developer", "GitHub", "Workspace"]

    static func load(
        defaults: UserDefaults = .standard,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        if let stored = defaults.stringArray(forKey: defaultsKey) {
            return normalized(stored.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0, isDirectory: true) })
        }
        let existing = defaultNames.map { home.appendingPathComponent($0, isDirectory: true) }.filter { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        return normalized(existing)
    }

    static func save(_ folders: [URL], defaults: UserDefaults = .standard) {
        defaults.set(normalized(folders).map(\.path), forKey: defaultsKey)
    }

    /// Resolved, de-duplicated, without `/` and without folders nested in another one.
    static func normalized(_ folders: [URL]) -> [URL] {
        let resolved: [URL] = folders
            .map { $0.resolvingSymlinksInPath().standardizedFileURL }
            .filter { $0.path != "/" }
            .sorted { (lhs: URL, rhs: URL) -> Bool in
                let left = lhs.path, right = rhs.path
                if left.count != right.count { return left.count < right.count }
                return left < right
            }
        var accepted: [URL] = []
        for folder in resolved where !accepted.contains(where: { folder.path == $0.path || folder.path.hasPrefix($0.path + "/") }) {
            accepted.append(folder)
        }
        return accepted.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
