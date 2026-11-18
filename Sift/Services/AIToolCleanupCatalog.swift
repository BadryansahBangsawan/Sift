import Foundation

/// Every path the "AI tools" category may offer and remove.
///
/// The scanner builds items from this list, and the cleaner re-derives the
/// entry from an item's path immediately before removal. Only an exact path in
/// `specs(home:)` or an exact session shape
/// (`<root>/<project>/<uuid>.jsonl`, `<root>/<project>/<uuid>/`,
/// `<root>/<project>/<timestamp>_<uuid>.jsonl`, …) is accepted — never a glob
/// or a bare directory that merely sits under `~/.claude` or `~/.omp`.
///
/// Everything that is the user's work or configuration — `memory/`, skills,
/// plugins, hooks, extensions, settings, credentials, databases — is refused
/// by `isNeverTouch(_:)` before allow-list matching, so a future target edit
/// cannot quietly start deleting it.
enum AIToolCleanupCatalog {
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    /// A transcript modified this recently is treated as still open and is not
    /// offered for removal.
    static let openSessionWindow: TimeInterval = 10 * 60

    enum AITool: String, CaseIterable {
        case claudeDesktop, claudeCode, omp, chatGPT, cursor, windsurf, vscode, codex, gemini, ollama, lmStudio

        /// Rail/detail grouping order: desktop apps, coding agents, local models.
        var order: Int {
            switch self {
            case .claudeDesktop: return 0
            case .claudeCode: return 1
            case .omp: return 2
            case .chatGPT: return 3
            case .cursor: return 4
            case .windsurf: return 5
            case .vscode: return 6
            case .codex: return 7
            case .gemini: return 8
            case .ollama: return 9
            case .lmStudio: return 10
            }
        }
    }

    struct Spec: Hashable {
        let path: String
        let name: String
        let tool: AITool
        /// Opt-in items (session/chat history, the Claude VM image) are never
        /// pre-selected and are moved to the Trash, not unlinked.
        let isOptIn: Bool
        let note: String?
        /// Bundle identifier of the app that must not be running while this
        /// path is removed.
        let requiresQuitBundleID: String?
        let companionPaths: [String]
    }

    struct SessionLocation {
        let root: String
        let tool: AITool
        let note: String
        /// omp transcripts are named `<timestamp>_<uuid>.jsonl`; Claude Code
        /// uses a bare UUID.
        let hasTimestampPrefix: Bool
    }

    // MARK: - Targets

    /// Absolute, exact paths for caches and logs (pre-selected) and for the
    /// opt-in history files. Existing-ness is checked by the scanner.
    static func specs(home: String) -> [Spec] {
        var specs: [Spec] = []

        func add(
            _ relativePath: String,
            _ name: String,
            tool: AITool,
            isOptIn: Bool = false,
            note: String? = nil,
            requiresQuit: Bool = false
        ) {
            specs.append(Spec(
                path: "\(home)/\(relativePath)",
                name: name,
                tool: tool,
                isOptIn: isOptIn,
                note: note,
                requiresQuitBundleID: requiresQuit ? claudeBundleID : nil,
                companionPaths: []
            ))
        }

        let claudeDesktop = "Library/Application Support/Claude"
        add("\(claudeDesktop)/Cache", String(localized: "Claude Desktop Cache"), tool: .claudeDesktop)
        add("\(claudeDesktop)/Code Cache", String(localized: "Claude Desktop Code Cache"), tool: .claudeDesktop)
        add("\(claudeDesktop)/GPUCache", String(localized: "Claude Desktop GPU Cache"), tool: .claudeDesktop)
        add("\(claudeDesktop)/DawnWebGPUCache", String(localized: "Claude Desktop Dawn WebGPU Cache"), tool: .claudeDesktop)
        add("\(claudeDesktop)/DawnGraphiteCache", String(localized: "Claude Desktop Dawn Graphite Cache"), tool: .claudeDesktop)
        add("\(claudeDesktop)/GraphiteDawnCache", String(localized: "Claude Desktop Graphite Dawn Cache"), tool: .claudeDesktop)
        add(
            "\(claudeDesktop)/vm_bundles",
            String(localized: "Claude VM image (re-downloads when needed)"),
            tool: .claudeDesktop,
            isOptIn: true,
            note: String(localized: "Re-downloads when needed. Quit Claude to remove it."),
            requiresQuit: true
        )
        add("Library/Logs/Claude", String(localized: "Claude Logs"), tool: .claudeDesktop)
        add(
            "Library/Caches/com.anthropic.claudefordesktop",
            String(localized: "Claude Desktop Web Cache"),
            tool: .claudeDesktop
        )

        add(
            "Library/Caches/claude-cli-nodejs",
            String(localized: "Claude Code CLI Cache"),
            tool: .claudeCode
        )
        add(".claude/shell-snapshots", String(localized: "Claude Code Shell Snapshots"), tool: .claudeCode)
        add(".claude/paste-cache", String(localized: "Claude Code Paste Cache"), tool: .claudeCode)
        add(".claude/telemetry", String(localized: "Claude Code Telemetry"), tool: .claudeCode)
        add(".claude/cache", String(localized: "Claude Code Cache"), tool: .claudeCode)
        add(".claude/debug", String(localized: "Claude Code Debug Logs"), tool: .claudeCode)
        add(
            ".claude/file-history",
            String(localized: "Claude Code Rewind History (Optional)"),
            tool: .claudeCode,
            isOptIn: true,
            note: String(localized: "Recoverable rewind data — not selected by default")
        )
        add(
            ".claude/history.jsonl",
            String(localized: "Claude Code Prompt History (Optional)"),
            tool: .claudeCode,
            isOptIn: true,
            note: String(localized: "Prompt history — not selected by default")
        )

        add(".omp/logs", String(localized: "omp Logs"), tool: .omp)

        add("Library/Caches/com.openai.chat", String(localized: "ChatGPT Cache"), tool: .chatGPT)

        // Editors in the VS Code family share the same regenerable cache
        // folder names. Only the ones that exist become items.
        let editors: [(name: String, tool: AITool, root: String)] = [
            ("Cursor", .cursor, "Library/Application Support/Cursor"),
            ("Windsurf", .windsurf, "Library/Application Support/Windsurf"),
            ("VS Code", .vscode, "Library/Application Support/Code"),
        ]
        let editorCaches: [(folder: String, namePattern: String)] = [
            ("Cache", "%@ Cache"),
            ("CachedData", "%@ Cached Data"),
            ("Code Cache", "%@ Code Cache"),
            ("GPUCache", "%@ GPU Cache"),
            ("logs", "%@ Logs"),
        ]
        for editor in editors {
            for cache in editorCaches {
                add(
                    "\(editor.root)/\(cache.folder)",
                    String(format: NSLocalizedString(cache.namePattern, comment: ""), editor.name),
                    tool: editor.tool
                )
            }
        }

        add(".codex/log", String(localized: "Codex Logs"), tool: .codex)
        add(
            ".codex/sessions",
            String(localized: "Codex Sessions (Optional)"),
            tool: .codex,
            isOptIn: true,
            note: String(localized: "Session history — not selected by default")
        )
        add(".gemini/tmp", String(localized: "Gemini CLI Temp Files"), tool: .gemini)

        // Ollama and LM Studio keep the targets and names they had before this
        // category grew, so existing cleanup history and exclusions still map.
        add(".ollama/logs", String(localized: "Ollama Logs"), tool: .ollama)
        add("Library/Caches/ollama", String(localized: "Ollama Cache"), tool: .ollama)
        add("Library/Caches/com.electron.ollama", String(localized: "Ollama Electron Cache"), tool: .ollama)
        add("Library/WebKit/com.electron.ollama", String(localized: "Ollama WebKit Data"), tool: .ollama)
        add(
            "Library/Saved Application State/com.electron.ollama.savedState",
            String(localized: "Ollama Saved State"),
            tool: .ollama
        )
        add(
            ".ollama/history",
            String(localized: "Ollama CLI Prompt History (Optional)"),
            tool: .ollama,
            isOptIn: true,
            note: String(localized: "Prompt history — not selected by default")
        )
        add(".lmstudio/server-logs", String(localized: "LM Studio Server Logs"), tool: .lmStudio)
        add(
            ".lmstudio/conversations",
            String(localized: "LM Studio Conversations (Optional)"),
            tool: .lmStudio,
            isOptIn: true,
            note: String(localized: "Chat history — not selected by default")
        )

        return specs
    }

    // MARK: - Sessions

    static func sessionLocations(home: String) -> [SessionLocation] {
        [
            SessionLocation(
                root: "\(home)/.claude/projects",
                tool: .claudeCode,
                note: String(localized: "Session history — not selected by default"),
                hasTimestampPrefix: false
            ),
            SessionLocation(
                root: "\(home)/.omp/agent/sessions",
                tool: .omp,
                note: String(localized: "Session history — not selected by default"),
                hasTimestampPrefix: true
            ),
        ]
    }

    /// The companion of a transcript: `<uuid>.jsonl` ⇄ `<uuid>/`.
    static func sessionCompanions(for path: String) -> [String] {
        if path.hasSuffix(".jsonl") {
            return [String(path.dropLast(".jsonl".count))]
        }
        return [path + ".jsonl"]
    }

    /// The project folder a session lives in, or nil when the path is not
    /// exactly `<root>/<project>/<file>` with a sane project name.
    static func sessionProject(for path: String, location: SessionLocation) -> String? {
        let prefix = location.root + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let relative = path.dropFirst(prefix.count)
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let project = String(parts[0])
        guard !project.isEmpty,
              project != "memory",
              !project.hasPrefix("."),
              !project.contains(".."),
              !isNeverTouch(project)
        else { return nil }
        return project
    }

    /// A single session entry (transcript file or its companion folder).
    static func sessionSpec(for path: String, home: String) -> Spec? {
        for location in sessionLocations(home: home) {
            guard let project = sessionProject(for: path, location: location) else { continue }
            let fileName = (path as NSString).lastPathComponent
            guard isSessionFileName(fileName, hasTimestampPrefix: location.hasTimestampPrefix) else { continue }
            return Spec(
                path: path,
                name: project,
                tool: location.tool,
                isOptIn: true,
                note: location.note,
                requiresQuitBundleID: nil,
                companionPaths: sessionCompanions(for: path)
            )
        }
        return nil
    }

    /// `<uuid>.jsonl` / `<uuid>` for Claude Code,
    /// `<timestamp>_<uuid>.jsonl` / `<timestamp>_<uuid>` for omp.
    static func isSessionFileName(_ name: String, hasTimestampPrefix: Bool) -> Bool {
        let base = name.hasSuffix(".jsonl") ? String(name.dropLast(".jsonl".count)) : name
        if !hasTimestampPrefix {
            return UUID(uuidString: base) != nil
        }
        guard let separator = base.lastIndex(of: "_"),
              separator > base.startIndex,
              UUID(uuidString: String(base[base.index(after: separator)...])) != nil
        else { return false }
        let stamp = base[..<separator]
        return stamp.contains("T") && !stamp.contains("/")
    }

    /// Readable project name from a Claude Code encoded directory such as
    /// `-Users-bbbadry--pencil-documents-282c4a1f-…`.
    static func projectDisplayName(fromEncodedDirectory name: String) -> String {
        let tokens = name
            .split(separator: "-")
            .map(String.init)
            .filter { token in
                guard token.count > 1 else { return false }
                // Drop UUID fragments and hash-like runs.
                return token.range(of: "^[0-9a-fA-F]{6,}$", options: .regularExpression) == nil
            }
        guard !tokens.isEmpty else { return name }
        return tokens.suffix(2).joined(separator: "-")
    }

    static func sessionDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Safety

    /// Paths that hold the user's work, settings, credentials or databases.
    /// Refused before any allow-list match and never offered as items.
    static func isNeverTouch(_ path: String) -> Bool {
        let components = (path as NSString).pathComponents
        let forbiddenDirectories: Set<String> = ["memory", "skills", "plugins", "hooks", "extensions"]
        if components.contains(where: forbiddenDirectories.contains) { return true }
        guard let last = components.last, !last.isEmpty else { return true }
        if last.hasPrefix(".credentials") { return true }
        if last.hasSuffix(".db") || last.hasSuffix(".db-shm") || last.hasSuffix(".db-wal")
            || last.hasSuffix(".db-journal") {
            return true
        }
        if last.hasSuffix(".lock") { return true }
        let forbiddenFiles: Set<String> = [
            "settings.json", "CLAUDE.md", "AGENTS.md", "keybindings.json",
            "config.json", "config.yml", "config.yaml", "config.toml",
            "auth.json", "mcp.json", "models.yml", "GEMINI.md",
            "remote-settings.json", "policy-limits.json",
        ]
        return forbiddenFiles.contains(last)
    }

    /// The allow-list entry for a path, or nil. `path` must already be
    /// normalized (no `..`, no NUL bytes) and not be a never-touch path.
    static func entry(for path: String, home: String) -> Spec? {
        guard !path.isEmpty,
              !path.utf8.contains(0),
              path == (path as NSString).standardizingPath,
              !isNeverTouch(path)
        else { return nil }
        if let exact = specs(home: home).first(where: { $0.path == path }) {
            return exact
        }
        return sessionSpec(for: path, home: home)
    }

    /// Whether the cleaner may remove this item: the path must resolve to an
    /// allow-list entry and every companion must be that entry's own
    /// companion, not an arbitrary extra path.
    static func accepts(item: CleanableItem, home: String) -> Bool {
        guard let entry = entry(for: item.path, home: home) else { return false }
        return item.companionPaths.allSatisfy { companion in
            companion == (companion as NSString).standardizingPath
                && !isNeverTouch(companion)
                && entry.companionPaths.contains(companion)
        }
    }

    /// Whether a session transcript is live work rather than history.
    ///
    /// The scan only offers transcripts untouched for `openSessionWindow`, and
    /// it records that timestamp on the row. A transcript written again after
    /// the scan belongs to a session the user resumed, so the cleaner refuses
    /// it instead of moving it out of the folder its agent is appending to.
    /// A row without a scan timestamp falls back to the window from `now`.
    static func isOpenSession(
        path: String,
        home: String,
        listedAt: Date?,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> Bool {
        guard sessionSpec(for: path, home: home) != nil else { return false }
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date
        else { return false }
        if let listedAt {
            // One second of tolerance: a metadata read can round the
            // modification date written by the scan.
            return modified.timeIntervalSince(listedAt) > 1
        }
        return now.timeIntervalSince(modified) < openSessionWindow
    }

    /// Bundle identifier that must not be running while `path` is removed.
    static func quitRequiredBundleID(forPath path: String, home: String) -> String? {
        entry(for: path, home: home)?.requiresQuitBundleID
    }
}
