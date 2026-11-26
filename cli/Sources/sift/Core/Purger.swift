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
        let relative = String(artifact.path.dropFirst(repository.path.count + 1))
        guard !relative.isEmpty else { return false }

        let tracked = Shell.run(
            git,
            [safeGitOption, "-C", repository.path, "ls-files", "-z", "--", relative],
            timeout: 10
        )
        guard tracked.status == 0 else { return false }
        if !tracked.out.isEmpty { return false }

        let ignored = Shell.run(
            git,
            [safeGitOption, "-C", repository.path, "check-ignore", "-q", "--", relative],
            timeout: 10
        )
        return ignored.status == 0
    }

    /// `-c core.fsmonitor=false` stops a repository's own config from running a
    /// program while git reads the index.
    static let safeGitOption = "-ccore.fsmonitor=false"

    /// The nearest ancestor holding `.git`, directory or worktree pointer file.
    static func repositoryRoot(containing folder: URL) -> URL? {
        var path = folder.standardizedFileURL.path
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

    /// Never `/usr/bin/git`: on a Mac without developer tools that stub asks to
    /// install them. Mirrors the app's executable lookup.
    static func gitExecutable() -> String? {
        var candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git"]
        if let developer = developerDirectory() {
            candidates.append(developer + "/usr/bin/git")
        }
        candidates.append("/Library/Developer/CommandLineTools/usr/bin/git")
        let fileManager = FileManager.default
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private static func developerDirectory() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
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
