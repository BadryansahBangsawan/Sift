import Foundation

/// Safety policy for entries directly under the system temporary directories.
/// macOS itself periodically clears these, but "anything in /tmp is junk" is
/// false on a working machine: the owner's /tmp holds live git worktrees
/// (tens of GB) and other tools' scratch state. An entry is only offered when
/// it is provably unused: owned by the current user, a plain file or folder,
/// quiet for at least three days, and free of repositories and sockets.
enum TmpJunkPolicy {
    /// /tmp is a symlink to /private/tmp on macOS; the real path is listed so
    /// entries are not offered twice under two spellings.
    static let roots = ["/private/tmp", "/private/var/tmp"]

    /// Same idea as macOS's own periodic /tmp cleanup.
    static let staleAfter: TimeInterval = 3 * 24 * 60 * 60

    /// Bounded walk. Hitting it means the entry could not be verified, and an
    /// unverifiable entry is never offered.
    static let maxWalkEntries = 20_000

    /// A repository or worktree at the root, or nested up to this depth, makes
    /// the entry live work.
    static let gitInspectionDepth = 3

    struct Inspection {
        let size: Int64
        let newestModification: Date?
        let containsGit: Bool
        let containsSocket: Bool
        let hitWalkCap: Bool
        let rejectionReason: String?

        var isOfferable: Bool { rejectionReason == nil }
    }

    /// True when `path` sits inside one of the managed temp roots. Both path
    /// spellings are accepted: /tmp is a symlink to /private/tmp, and
    /// Foundation may resolve one to the other depending on the process.
    static func contains(_ path: String) -> Bool {
        let candidates = [
            (path as NSString).standardizingPath,
            (path as NSString).resolvingSymlinksInPath,
        ]
        return candidates.contains { candidate in
            rootPrefixes.contains { candidate.hasPrefix($0) }
        }
    }

    private static let rootPrefixes: [String] = roots.flatMap { root in
        [root + "/", (root as NSString).resolvingSymlinksInPath + "/"]
    }

    static func inspect(
        path: String,
        now: Date,
        fileManager: FileManager = .default
    ) -> Inspection {
        func rejected(_ reason: String, size: Int64 = 0, newest: Date? = nil) -> Inspection {
            Inspection(
                size: size,
                newestModification: newest,
                containsGit: false,
                containsSocket: false,
                hitWalkCap: false,
                rejectionReason: reason
            )
        }

        let entryURL = URL(fileURLWithPath: path)
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileType = attributes[.type] as? FileAttributeType else {
            return rejected("cannot read its attributes")
        }
        guard fileType != .typeSymbolicLink else {
            return rejected("is a symbolic link")
        }
        guard fileType == .typeRegular || fileType == .typeDirectory else {
            return rejected("is not a regular file or directory")
        }
        guard let ownerID = attributes[.ownerAccountID] as? NSNumber,
              ownerID.uint32Value == getuid() else {
            return rejected("is not owned by the current user")
        }

        if fileType == .typeRegular {
            let modified = attributes[.modificationDate] as? Date
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard let modified, now.timeIntervalSince(modified) >= staleAfter else {
                return rejected("was modified less than three days ago", size: size, newest: modified)
            }
            return Inspection(
                size: size,
                newestModification: modified,
                containsGit: false,
                containsSocket: false,
                hitWalkCap: false,
                rejectionReason: nil
            )
        }

        // Directory: one bounded walk collects size, the newest modification
        // anywhere inside, repositories, and sockets, so the scan pays for the
        // subtree once.
        let baseDepth = entryURL.pathComponents.count
        var size: Int64 = 0
        var newest = attributes[.modificationDate] as? Date
        var containsGit = false
        var containsSocket = false
        var visited = 0
        var hitWalkCap = false

        let keys: [URLResourceKey] = [
            .totalFileAllocatedSizeKey,
            .fileSizeKey,
            .fileResourceTypeKey,
            .contentModificationDateKey,
        ]
        if let enumerator = fileManager.enumerator(
            at: entryURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) {
            for case let childURL as URL in enumerator {
                if Task.isCancelled { break }
                visited += 1
                if visited > maxWalkEntries {
                    hitWalkCap = true
                    break
                }
                let depth = childURL.pathComponents.count - baseDepth
                if childURL.lastPathComponent == ".git", depth <= gitInspectionDepth {
                    containsGit = true
                }
                guard let values = try? childURL.resourceValues(forKeys: Set(keys)) else { continue }
                if values.fileResourceType == .socket {
                    containsSocket = true
                }
                if let modified = values.contentModificationDate, modified > (newest ?? .distantPast) {
                    newest = modified
                }
                if values.fileResourceType == .regular {
                    size += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
                }
            }
        }

        func inspected(_ reason: String?) -> Inspection {
            Inspection(
                size: size,
                newestModification: newest,
                containsGit: containsGit,
                containsSocket: containsSocket,
                hitWalkCap: hitWalkCap,
                rejectionReason: reason
            )
        }

        if hitWalkCap {
            return inspected("holds more than \(maxWalkEntries) entries, so it could not be verified")
        }
        if containsGit {
            return inspected("contains a git repository or worktree")
        }
        if containsSocket {
            return inspected("contains a socket for a running service")
        }
        guard let newest, now.timeIntervalSince(newest) >= staleAfter else {
            return inspected("was modified less than three days ago")
        }
        return inspected(nil)
    }
}
