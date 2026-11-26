import Foundation

enum OrphanSafetyPolicy {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    // Conservative allowlist: only volatile data directories.
    static let allowedRoots: [String] = [
        "\(home)/Library/Caches",
        "\(home)/Library/Logs",
        "\(home)/Library/Saved Application State",
        "\(home)/Library/HTTPStorages",
        "\(home)/Library/WebKit",
        "\(home)/Library/Application Support/CrashReporter",
        "/Library/Caches",
        "/Library/Logs",
    ]

    private static let blockedFragments: [String] = [
        "/Library/Preferences",
        "/Library/PreferencePanes",
        "/Library/Containers",
        "/Library/Group Containers",
        "/Library/Application Scripts",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
        "/Library/PrivilegedHelperTools",
        "/Library/Keychains",
        "/Library/Mail",
        "/Library/Safari",
        "/Library/Messages",
        "/Library/Calendars",
        "/Library/Accounts",
        "/Library/Mobile Documents",
        "/Library/CloudStorage",
    ]

    static func isSafeCandidate(_ url: URL) -> Bool {
        let path = normalizedPath(url)
        let lowerPath = path.lowercased()

        // Belt-and-suspenders: reject any high-risk home dotpath (defined in
        // Conditions.swift). The allowedRoots filter below would catch most
        // of these, but this early block keeps the rule obvious.
        for root in highRiskHomeDotPaths {
            if path == root || path.hasPrefix(root + "/") {
                return false
            }
        }

        // Require the match to land STRICTLY inside the allowed root, not at a
        // sibling like /tmpfoo. Trailing "/" prevents hasPrefix from matching
        // sibling directories whose names merely start with the root name.
        guard allowedRoots.contains(where: { root in
            let rootWithSlash = root.lowercased() + "/"
            return lowerPath.hasPrefix(rootWithSlash)
        }) else {
            return false
        }

        if blockedFragments.contains(where: { lowerPath.contains($0.lowercased()) }) {
            return false
        }

        let name = url.lastPathComponent.lowercased()
        if name.hasPrefix("com.apple.") || name == ".globalpreferences.plist" {
            return false
        }

        // Finder and WebKit metadata, and the Swift toolchain's own package
        // cache: no app owns them, so an uninstalled app's absence says
        // nothing about them.
        if name == ".ds_store" {
            return false
        }
        let sharedWebKit = "\(home)/Library/WebKit/LocalStorage"
        if lowerPath == sharedWebKit.lowercased() {
            return false
        }
        let swiftPMCache = "\(home)/Library/Caches/org.swift.swiftpm"
        if lowerPath == swiftPMCache.lowercased() {
            return false
        }

        return true
    }

    private static func normalizedPath(_ url: URL) -> String {
        let standardized = url.standardizedFileURL
        return standardized.resolvingSymlinksInPath().path
    }
}

/// Moves an orphan to the Trash (or hands it to the admin pass) while writing
/// the audit row. The trash closure is injectable so tests never touch the
/// real Trash.
enum OrphanRemover {
    enum Outcome: Sendable, Equatable {
        case removed
        case needsAdmin
        case failed
    }

    static func remove(
        _ url: URL,
        log: CleanupLog,
        isSafe: (URL) -> Bool = OrphanSafetyPolicy.isSafeCandidate,
        trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) -> Outcome {
        guard isSafe(url) else {
            log.record(
                source: "orphans",
                category: "Orphans",
                action: .skipped,
                path: url.path,
                reason: "Unsafe orphan path."
            )
            return .failed
        }
        do {
            try trash(url)
            log.record(source: "orphans", category: "Orphans", action: .trashed, path: url.path)
            return .removed
        } catch {
            let nsError = error as NSError
            let permissionDeniedCodes = [
                NSFileReadNoPermissionError,
                NSFileWriteNoPermissionError,
                NSFileWriteUnknownError,
                257,
                513,
            ]
            if permissionDeniedCodes.contains(nsError.code) {
                return .needsAdmin
            }
            log.record(
                source: "orphans",
                category: "Orphans",
                action: .failed,
                path: url.path,
                reason: error.localizedDescription
            )
            return .failed
        }
    }

    /// Writes the outcome of the administrator batch after it returns.
    static func recordAdminOutcome(urls: [URL], succeeded: Bool, log: CleanupLog) {
        for url in urls {
            if succeeded, !FileManager.default.fileExists(atPath: url.path) {
                log.record(source: "orphans", category: "Orphans", action: .removedWithAdmin, path: url.path)
            } else {
                log.record(
                    source: "orphans",
                    category: "Orphans",
                    action: .failed,
                    path: url.path,
                    reason: succeeded ? "Survived administrator removal." : "Administrator removal failed."
                )
            }
        }
    }
}
