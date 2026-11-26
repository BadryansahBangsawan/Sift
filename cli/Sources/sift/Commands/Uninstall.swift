import ArgumentParser
import Darwin
import Foundation

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove an app bundle and the files that carry its bundle identifier.",
        discussion: """
        Review first, then confirm. Matching is by exact bundle identifier, never
        by name similarity: only files whose own name is the identifier (or its
        Preferences plist) are offered, so a neighbouring app's data is never
        swept up. Deletion is permanent — files do not go to the Trash.
        """
    )

    @Argument(help: "Path to the .app bundle to remove.")
    var appPath: String

    @Flag(name: .long, help: "Remove without review or confirmation (the whole matched set).")
    var force = false

    @Flag(name: .customLong("dry-run"), help: "Report what would be removed; never delete.")
    var dryRun = false

    @Flag(name: .long, help: "Emit machine-readable JSON and exit (never deletes).")
    var json = false

    @Flag(name: .long, help: "Use a numbered line-based selector instead of the fullscreen review.")
    var plain = false

    /// Every top-level folder that can hold bundle-identifier-named data.
    /// Scoped to the user's own Home so no system or other-user data is reachable.
    private static var librarySubtrees: [String] {
        return [
            "Preferences",
            "Caches",
            "Application Support",
            "Containers",
            "Group Containers",
            "Logs",
            "Saved Application State",
            "WebKit",
            "HTTPStorages",
            "Cookies",
            "LaunchAgents",
            "Application Scripts",
            "Application State",
            "Services",
        ]
    }

    func validate() throws {
        guard appPath.hasPrefix("/") else {
            throw ValidationError("Path must be absolute: \(appPath)")
        }
        guard appPath.hasSuffix(".app") else {
            throw ValidationError("Not an app bundle: \(appPath)")
        }
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw ValidationError("No such app: \(appPath)")
        }
    }

    func run() throws {
        guard appPath.hasPrefix("/") else {
            throw ValidationError("Path must be absolute: \(appPath)")
        }
        guard appPath.hasSuffix(".app") else {
            throw ValidationError("Not an app bundle: \(appPath)")
        }
        let bundleID = try Self.bundleIdentifier(ofAppAt: appPath)

        if bundleID.hasPrefix("com.apple.") || appPath.hasPrefix("/System") || appPath.hasPrefix("/Library/Apple") {
            throw ValidationError("System apps cannot be uninstalled.")
        }
        if let pid = try Self.runningProcessID(forAppAt: appPath) {
            throw ValidationError(
                "Quit \(((appPath as NSString).lastPathComponent)) first — it is running as PID \(pid)."
            )
        }

        let mode = CleanupCommandPolicy.mode(
            force: force,
            dryRun: dryRun,
            json: json,
            plain: plain
        )
        guard mode != .unavailable else {
            throw ValidationError("Interactive review requires a terminal. Re-run with --force to remove the matched items, or use --dry-run or --json for a read-only report.")
        }

        let ignore = try IgnoreStore(fileURL: AppPaths.ignoreFile, legacyFileURL: AppPaths.legacyIgnoreFile)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let matched = Self.leftoverPaths(for: bundleID, home: home, ignore: ignore)
        var scan = Self.scan(appPath: appPath, bundleID: bundleID, leftovers: matched)
        if mode == .forced {
            // `--force` means "remove the whole matched set": the review list
            // starts unselected, so it has to be opted in before printing.
            scan = Self.selectAll(in: scan)
        }

        if json {
            print(try report(scan))
            return
        }

        print("")
        print(Term.bold(Term.sanitize(appPath)))
        print(Term.dim("Bundle identifier: ") + Term.sanitize(bundleID))
        Render.scanResults([scan])
        Render.selectionLine([scan])

        if dryRun {
            // A real uninstall removes the whole matched set (that is what
            // --force selects), so the dry run must count the same set instead
            // of the unselected review state.
            let selected = Self.selectAll(in: scan).selectedItems
            let out = Cleaner.remove(selected, ignore: ignore, dryRun: true, allowingAppBundles: true)
            Render.cleanupSummary(out, dryRun: true)
            return
        }

        let reviewed: [CategoryScan]
        switch mode {
        case .forced:
            reviewed = [scan]
        case .fullscreen:
            guard let selection = try InteractiveReview.select([scan], title: "Choose what to remove") else {
                print(Term.dim("Cancelled. Nothing removed."))
                return
            }
            reviewed = selection
        case .plain:
            guard let selection = try PlainSelectionReview.select([scan], title: "Choose what to remove") else {
                print(Term.dim("Cancelled. Nothing removed."))
                return
            }
            reviewed = selection
        case .reportOnly, .unavailable:
            return
        }

        let selected = reviewed.flatMap { $0.selectedItems }
        guard !selected.isEmpty else {
            print(Term.dim("No items selected. Nothing removed."))
            return
        }

        if mode != .forced {
            Render.deletionReview(reviewed)
            let total = ByteCount.human(selected.reduce(Int64(0)) { $0 + $1.sizeBytes })
            guard Term.confirm("Permanently remove \(selected.count) items (\(total))?", default: false) else {
                print(Term.dim("Cancelled. Nothing removed."))
                return
            }
        }

        let out = Cleaner.remove(selected, ignore: ignore, dryRun: false, allowingAppBundles: true)
        Render.cleanupSummary(out, dryRun: false)
        if out.hadFailures { throw ExitCode.failure }
    }

    // MARK: - Bundle identity

    static func bundleIdentifier(ofAppAt path: String) throws -> String {
        let plistURL = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = value as? [String: Any],
              let identifier = (dictionary["CFBundleIdentifier"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !identifier.isEmpty
        else {
            throw ValidationError("Not an app bundle or no bundle identifier: \(path)")
        }
        return identifier
    }

    /// PID of a process whose executable lives inside this bundle. Deleting a
    /// running app leaves macOS pointing at a vanished bundle and can corrupt
    /// the app's own saved state, so this refuses instead of racing.
    ///
    /// Compares the executable's path literally. A pattern tool such as
    /// `pgrep -f` reads the bundle path as a regular expression, so an app at
    /// "Foo (Beta).app" or "Foo.Bar.app" could be missed or mistaken for
    /// another process and then deleted while it was running.
    ///
    /// Throws when the process table cannot be read: "could not check" must
    /// never be treated as "not running" by a command that deletes.
    static func runningProcessID(forAppAt path: String) throws -> Int? {
        var candidates = [
            URL(fileURLWithPath: path).standardizedFileURL.path,
            URL(fileURLWithPath: path).resolvingSymlinksInPath().path,
        ]
        // The kernel reports /private/var/… even when the caller names /var/…,
        // and Foundation keeps that alias, so ask the filesystem too.
        var canonical = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if realpath(path, &canonical) != nil { candidates.append(String(cString: canonical)) }
        let prefixes = Set(candidates).map { $0.hasSuffix("/") ? $0 : $0 + "/" }

        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else {
            throw ValidationError("Could not read the process list, so Sift cannot tell whether the app is running. Nothing was removed.")
        }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 32)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count) * Int32(MemoryLayout<pid_t>.size))
        }
        guard count > 0 else {
            throw ValidationError("Could not read the process list, so Sift cannot tell whether the app is running. Nothing was removed.")
        }

        let ownPID = getpid()
        var executablePath = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(count)) where pid > 0 && pid != ownPID {
            let length = proc_pidpath(pid, &executablePath, UInt32(executablePath.count))
            guard length > 0 else { continue }
            let executable = String(cString: executablePath)
            if prefixes.contains(where: { executable.hasPrefix($0) }) { return Int(pid) }
        }
        return nil
    }

    // MARK: - Matching

    /// Keeps only the candidates whose own file name is the bundle identifier
    /// (or `<id>.plist`). Anything else belongs to a different app.
    static func matches(for bundleID: String, candidates: [String]) -> [String] {
        let target = bundleID.lowercased()
        let plistTarget = target + ".plist"
        return candidates.filter { candidate in
            let name = (candidate as NSString).lastPathComponent.lowercased()
            return name == target || name == plistTarget
        }
    }

    static func leftoverPaths(for bundleID: String, home: String, ignore: IgnoreStore) -> [String] {
        let fm = FileManager.default
        var candidates: [String] = []

        for subtree in librarySubtrees {
            let directory = home + "/Library/" + subtree
            guard let children = try? fm.contentsOfDirectory(atPath: directory) else { continue }
            candidates.append(contentsOf: children.map { directory + "/" + $0 })
        }

        // Launch agents store the identifier in their Label, not necessarily in
        // the file name, so those plists are matched by content and must not go
        // through the name filter below.
        var labelMatched: [String] = []
        let agentsDirectory = home + "/Library/LaunchAgents"
        if let agents = try? fm.contentsOfDirectory(atPath: agentsDirectory) {
            for agent in agents where agent.hasSuffix(".plist") {
                let full = agentsDirectory + "/" + agent
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
                      let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                      let dictionary = value as? [String: Any],
                      let label = dictionary["Label"] as? String,
                      label.caseInsensitiveCompare(bundleID) == .orderedSame
                else { continue }
                labelMatched.append(full)
            }
        }

        var exact = matches(for: bundleID, candidates: candidates)
        for path in labelMatched where !exact.contains(path) { exact.append(path) }
        return exact.filter { path in
            !Safety.hasSymlinkComponent(path)
                && !Safety.isCloudOrDataless(path)
                && !Safety.isPathIgnored(path, ignore: ignore)
        }.sorted()
    }

    /// Builds the reviewable scan: the app bundle itself plus every matched
    /// leftover, none of them preselected.
    static func scan(appPath: String, bundleID: String, leftovers: [String]) -> CategoryScan {
        var groups: [ToolGroup] = []

        let bundleItem = ScanItem(
            path: appPath,
            sizeBytes: DirSizer.size(of: appPath),
            modified: DirSizer.modified(of: appPath),
            identity: Safety.fileIdentity(at: appPath),
            selected: false
        )
        groups.append(ToolGroup(tool: "Application", items: [bundleItem]))

        if !leftovers.isEmpty {
            let items = leftovers.map { path in
                ScanItem(
                    path: path,
                    sizeBytes: DirSizer.size(of: path),
                    modified: DirSizer.modified(of: path),
                    identity: Safety.fileIdentity(at: path),
                    selected: false
                )
            }
            groups.append(ToolGroup(tool: "Leftover data for \(bundleID)", items: items))
        }

        return CategoryScan(id: "uninstall", title: bundleID, groups: groups)
    }

    static func selectAll(in scan: CategoryScan) -> CategoryScan {
        var out = scan
        for groupIndex in out.groups.indices {
            for itemIndex in out.groups[groupIndex].items.indices {
                out.groups[groupIndex].items[itemIndex].selected = true
            }
        }
        return out
    }

    // MARK: - JSON

    private func report(_ scan: CategoryScan) throws -> String {
        struct Out: Encodable {
            struct Item: Encodable { let path: String; let sizeBytes: Int64; let group: String }
            let appPath: String
            let bundleID: String
            let items: [Item]
            let totalBytes: Int64
        }
        let items = scan.groups.flatMap { group in
            group.items.map { Out.Item(path: $0.path, sizeBytes: $0.sizeBytes, group: group.tool) }
        }
        let out = Out(
            appPath: appPath,
            bundleID: scan.title,
            items: items,
            totalBytes: items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(out), as: UTF8.self)
    }
}
