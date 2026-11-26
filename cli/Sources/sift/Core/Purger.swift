import Darwin
import Foundation

enum Purger {

    static let artifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".turbo", ".svelte-kit", ".angular", ".parcel-cache",
        "target", ".build", "DerivedData", "Pods",
        ".venv", "venv", "__pycache__", ".pytest_cache", ".mypy_cache", ".tox", ".ruff_cache",
        ".gradle",
    ]

    static let artifactPrefixes = ["cmake-build"]

    /// A generated folder's parent must hold one of these project files before
    /// the folder is offered. Mirrors the app's ProjectJunk rules; a leading
    /// `*` matches by suffix (`*.xcodeproj`). Names with no rule are not
    /// artifacts here.
    static let artifactMarkers: [String: [String]] = [
        "node_modules": ["package.json"],
        ".next": ["package.json"],
        ".nuxt": ["package.json"],
        ".turbo": ["package.json"],
        ".svelte-kit": ["package.json"],
        ".angular": ["package.json"],
        ".parcel-cache": ["package.json"],
        "target": ["Cargo.toml", "pom.xml", "build.sbt"],
        ".build": ["Package.swift"],
        "DerivedData": ["*.xcodeproj", "*.xcworkspace"],
        "Pods": ["Podfile"],
        ".gradle": ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"],
        ".tox": ["tox.ini", "pyproject.toml", "setup.cfg", "setup.py"],
        ".venv": pythonMarkers,
        "venv": pythonMarkers,
        "__pycache__": pythonMarkers,
        ".pytest_cache": pythonMarkers,
        ".mypy_cache": pythonMarkers,
        ".ruff_cache": pythonMarkers,
    ]

    private static let pythonMarkers = [
        "pyproject.toml", "requirements.txt", "setup.py", "setup.cfg", "Pipfile",
    ]

    /// The contents must look generated. Mirrors the app's ArtifactRule
    /// signatures; without this, a source folder that happens to share an
    /// artifact name and sits next to the marker would be deleted.
    static func hasContentSignature(for name: String, in folder: URL) -> Bool {
        let fm = FileManager.default
        if name.hasPrefix("cmake-build") {
            return anyOf(["CMakeCache.txt"])(folder, fm)
        }
        switch name {
        case "node_modules":
            return nodeModulesSignature(folder, fm)
        case ".next":
            return anyOf(["BUILD_ID", "cache"])(folder, fm)
        case ".nuxt", ".turbo", ".svelte-kit", ".angular", ".parcel-cache":
            return nonEmpty(folder, fm)
        case "target":
            return anyOf(["CACHEDIR.TAG", ".rustc_info.json", "classes", "maven-status", "maven-archiver", "streams"])(folder, fm)
        case ".build":
            return anyOf(["workspace-state.json", "debug.yaml", "release.yaml", ".lock"])(folder, fm)
        case "DerivedData":
            return derivedDataSignature(folder, fm)
        case "Pods":
            return anyOf(["Manifest.lock"])(folder, fm)
        case ".gradle":
            return gradleSignature(folder, fm)
        case ".venv", "venv":
            return anyOf(["pyvenv.cfg"])(folder, fm)
        case "__pycache__":
            return bytecodeOnly(folder, fm)
        case ".pytest_cache", ".mypy_cache", ".ruff_cache":
            return anyOf(["CACHEDIR.TAG"])(folder, fm)
        case ".tox":
            return toxSignature(folder, fm)
        default:
            return false
        }
    }

    private static func anyOf(_ entries: [String]) -> (URL, FileManager) -> Bool {
        { folder, _ in entries.contains { lexists(folder.appendingPathComponent($0)) } }
    }

    private static func nonEmpty(_ folder: URL, _ fm: FileManager) -> Bool {
        !((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty
    }

    private static func nodeModulesSignature(_ folder: URL, _ fm: FileManager) -> Bool {
        for state in [".package-lock.json", ".modules.yaml", ".yarn-state.yml", ".yarn-integrity"]
        where lexists(folder.appendingPathComponent(state)) {
            return true
        }
        let children = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().prefix(500)
        for child in children where !child.hasPrefix(".") {
            let childURL = folder.appendingPathComponent(child)
            if child.hasPrefix("@") {
                let scoped = ((try? fm.contentsOfDirectory(atPath: childURL.path)) ?? []).sorted().prefix(50)
                if scoped.contains(where: { isRegularFile(childURL.appendingPathComponent($0).appendingPathComponent("package.json")) }) {
                    return true
                }
            } else if isRegularFile(childURL.appendingPathComponent("package.json")) {
                return true
            }
        }
        return false
    }

    private static func derivedDataSignature(_ folder: URL, _ fm: FileManager) -> Bool {
        if anyOf(["Build", "Index.noindex", "ModuleCache.noindex", "info.plist"])(folder, fm) { return true }
        let children = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().prefix(200)
        return children.contains { lexists(folder.appendingPathComponent($0).appendingPathComponent("info.plist")) }
    }

    private static func gradleSignature(_ folder: URL, _ fm: FileManager) -> Bool {
        if lexists(folder.appendingPathComponent("buildOutputCleanup")) { return true }
        let children = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        return children.contains { name in
            let parts = name.split(separator: ".", omittingEmptySubsequences: false)
            return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
        }
    }

    private static func bytecodeOnly(_ folder: URL, _ fm: FileManager) -> Bool {
        guard let entries = try? fm.contentsOfDirectory(atPath: folder.path), !entries.isEmpty else { return false }
        return entries.allSatisfy { entry in
            isRegularFile(folder.appendingPathComponent(entry))
                && (entry.hasSuffix(".pyc") || entry.hasSuffix(".pyo"))
        }
    }

    private static func toxSignature(_ folder: URL, _ fm: FileManager) -> Bool {
        let children = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        return children.contains { child in
            lexists(folder.appendingPathComponent(child).appendingPathComponent("pyvenv.cfg"))
                || lexists(folder.appendingPathComponent(child).appendingPathComponent(".tox-info.json"))
        }
    }

    static func lexists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    static let defaultRoots = ["Projects", "Code", "dev", "GitHub", "Workspace"]
        .map { "\(Safety.home)/\($0)" }

    static func isArtifact(_ name: String) -> Bool {
        artifactNames.contains(name) || artifactPrefixes.contains { name.hasPrefix($0) }
    }

    static func projectMarkers(for name: String) -> [String]? {
        if name.hasPrefix("cmake-build") { return ["CMakeLists.txt"] }
        return artifactMarkers[name]
    }

    static func hasProjectMarker(for name: String, in project: URL) -> Bool {
        guard let markers = projectMarkers(for: name) else { return false }
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: project.path)) ?? []
        for marker in markers {
            if marker.hasPrefix("*") {
                let suffix = String(marker.dropFirst())
                if entries.contains(where: { $0.hasSuffix(suffix) }) { return true }
            } else if fm.fileExists(atPath: project.appendingPathComponent(marker).path) {
                return true
            }
        }
        return false
    }

    static func scan(roots: [String], olderThanDays: Int, ignore: IgnoreStore) -> CategoryScan {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        var byProject: [String: [ScanItem]] = [:]
        var order: [String] = []

        for rootURL in scanRoots(roots) {
            guard let en = fm.enumerator(at: rootURL,
                                         includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                         options: [.skipsPackageDescendants],
                                         errorHandler: { _, _ in true }) else { continue }

            for case let url as URL in en {
                let name = url.lastPathComponent
                let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if vals?.isSymbolicLink == true { en.skipDescendants(); continue }
                guard vals?.isDirectory == true else { continue }
                if en.level > 8 { en.skipDescendants(); continue }
                if Safety.isCloudOrDataless(url.path) || Safety.isPathIgnored(url.path, ignore: ignore) {
                    en.skipDescendants()
                    continue
                }

                if isArtifact(name) {
                    // The name alone proves nothing: `target` and `build` are
                    // ordinary source folder names too. Only offer the folder
                    // when the project file that generates it sits next to it.
                    guard hasProjectMarker(for: name, in: url.deletingLastPathComponent()) else { continue }
                    en.skipDescendants()
                    guard isOfferedByGit(url, project: url.deletingLastPathComponent()) else { continue }
                    guard hasContentSignature(for: name, in: url) else { continue }
                    if Safety.ignoredPathProtectsCandidate(url.path, ignore: ignore) { continue }
                    let measurement = DirSizer.measure(of: url.path)
                    guard measurement.status == .complete,
                          measurement.bytes >= CategoryScanner.minSize else { continue }
                    let mod = DirSizer.modified(of: url.path)
                    let old = (mod ?? .distantFuture) < cutoff
                    let project = projectLabel(url, level: en.level, root: rootURL)
                    let item = ScanItem(path: url.path, sizeBytes: measurement.bytes, modified: mod, selected: old)
                    byProject[project, default: []].append(item)
                    if !order.contains(project) { order.append(project) }
                }
            }
        }

        let groups = order.map { proj in
            ToolGroup(tool: proj, items: byProject[proj]!.sorted { $0.sizeBytes > $1.sizeBytes })
        }.sorted { $0.allBytes > $1.allBytes }
        return CategoryScan(id: "purge", title: "Project Artifacts", groups: groups)
    }

    /// Applies the app's git rule: an artifact inside a git work tree is offered
    /// only when git proves it is ignored and untracked. Outside a repository
    /// nothing changes. If git is unavailable while inside a repository, the
    /// folder is not offered: "could not prove" is never "safe to delete".
    static func isOfferedByGit(_ artifact: URL, project: URL) -> Bool {
        guard let repository = repositoryRoot(containing: project) else { return true }
        guard let git = gitExecutable() else { return false }
        let artifactPath = canonicalPath(artifact.path)
        let repositoryPath = canonicalPath(repository.path)
        guard artifactPath.hasPrefix(repositoryPath + "/") else { return false }
        let relative = String(artifactPath.dropFirst(repositoryPath.count + 1))
        guard !relative.isEmpty else { return false }

        let tracked = Shell.run(
            git,
            safeGitOptions + ["-C", repositoryPath, "ls-files", "-z", "--", relative],
            timeout: 10
        )
        guard tracked.status == 0 else { return false }
        if !tracked.out.isEmpty { return false }

        let ignored = Shell.run(
            git,
            safeGitOptions + ["-C", repositoryPath, "check-ignore", "-q", "--", relative],
            timeout: 10
        )
        return ignored.status == 0
    }

    /// `realpath` because Foundation keeps `/var` and `/private/var` apart,
    /// while the enumerator and git report different halves of the pair.
    static func canonicalPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if realpath(path, &buffer) != nil { return String(cString: buffer) }
        return (path as NSString).standardizingPath
    }

    /// `-c core.fsmonitor=false` stops a repository's own config from running a
    /// program while git reads the index.
    static let safeGitOptions = ["-c", "core.fsmonitor=false"]

    /// The nearest ancestor holding `.git`, directory or worktree pointer file.
    static func repositoryRoot(containing folder: URL) -> URL? {
        var path = canonicalPath(folder.path)
        while path.hasPrefix("/") {
            let current = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            if path == "/" { return nil }
            path = (path as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Resolves the git executable once for the lifetime of the process. A disk
    /// scan asks about every candidate inside a repository, so looking it up per
    /// candidate would spawn `xcode-select` hundreds of times.
    static let gitExecutableResolver = makeGitExecutableResolver(resolveGitExecutable)

    static func makeGitExecutableResolver(_ resolve: @escaping () -> String?) -> () -> String? {
        let lock = NSLock()
        var cached: String??
        return {
            lock.lock()
            defer { lock.unlock() }
            if let cached { return cached }
            let value = resolve()
            cached = .some(value)
            return value
        }
    }

    static func gitExecutable() -> String? {
        gitExecutableResolver()
    }

    /// Never `/usr/bin/git`: on a Mac without developer tools that stub asks to
    /// install them. Mirrors the app's executable lookup.
    private static func resolveGitExecutable() -> String? {
        var candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git"]
        if let developer = developerDirectory() {
            candidates.append(developer + "/usr/bin/git")
        }
        candidates.append("/Library/Developer/CommandLineTools/usr/bin/git")
        let fileManager = FileManager.default
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private static func developerDirectory() -> String? {
        let result = Shell.run("/usr/bin/xcode-select", ["-p"], timeout: 5)
        guard result.status == 0 else { return nil }
        let path = result.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }

    static func scanRoots(_ roots: [String]) -> [URL] {
        let candidates = roots.compactMap { root -> URL? in
            guard Safety.isValidScanRoot(root).ok else { return nil }
            return URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL
        }.sorted { $0.path.count < $1.path.count }
        var accepted: [URL] = []
        for candidate in candidates where !accepted.contains(where: {
            candidate.path == $0.path || candidate.path.hasPrefix($0.path + "/")
        }) {
            accepted.append(candidate)
        }
        return accepted
    }

    private static func projectLabel(_ url: URL, level: Int, root: URL) -> String {
        guard level > 1 else { return url.lastPathComponent }
        var u = url
        for _ in 0..<(level - 1) { u = u.deletingLastPathComponent() }
        return u.lastPathComponent
    }
}
