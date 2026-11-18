import ArgumentParser
import CryptoKit
import Foundation

struct Dupes: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find files with identical contents under a folder.",
        discussion: """
        Read-only. Files are compared by SHA-256 of their contents, so two files
        with the same name but different bytes never match. Hard links to one
        inode count as a single file: deleting them frees nothing. Nothing is
        ever deleted by this command — use --json or the listing to decide.
        """
    )

    @Argument(help: "Folder to scan. Defaults to your home folder.")
    var path: String?

    @Flag(name: .long, help: "Emit machine-readable JSON instead of a listing.")
    var json = false

    @Option(name: .long, help: "Ignore files smaller than this many bytes.")
    var minSize: Int64 = 1_048_576

    private static let chunkSize = 1_048_576

    func validate() throws {
        guard let path else { return }
        guard path.hasPrefix("/") else {
            throw ValidationError("Path must be absolute: \(path)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw ValidationError("No such folder: \(path)")
        }
        guard isDirectory.boolValue else {
            throw ValidationError("Not a folder: \(path)")
        }
    }

    func run() throws {
        let root = path ?? FileManager.default.homeDirectoryForCurrentUser.path
        if !json {
            Term.err(Term.dim("Scanning \(Render.shorten(root)) for files over \(ByteCount.human(minSize)) …"))
        }

        let candidates = Self.candidates(in: root, minSize: minSize)
        let hashed = Self.hashCandidates(candidates, announce: !json)
        let groups = Self.group(hashed)

        if json {
            print(try report(groups))
            return
        }

        guard !groups.isEmpty else {
            print(Term.green("No duplicate files found."))
            return
        }

        let wasted = groups.reduce(Int64(0)) { $0 + $1.wastedBytes }
        print("")
        print(
            Term.bold(ByteCount.human(wasted))
                + Term.dim(" recoverable across \(groups.count) group\(groups.count == 1 ? "" : "s")")
        )
        for group in groups {
            print("")
            print(
                Term.cyan(ByteCount.human(group.wastedBytes))
                    + Term.dim(" wasted · ")
                    + "\(group.paths.count) copies"
                    + Term.dim(" of \(ByteCount.human(group.size))")
            )
            for path in group.paths {
                print("  " + Render.sizeCol(group.size) + Term.sanitize(Render.shorten(path)))
            }
        }
        print("")
        print(Term.dim("Nothing was deleted. Remove copies yourself once you have picked which to keep."))
        print("")
    }

    // MARK: - Scanning

    struct Candidate {
        let path: String
        let size: Int64
        let identity: FileIdentity
    }

    static func candidates(in root: String, minSize: Int64) -> [Candidate] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else { return [] }

        var results: [Candidate] = []
        for case let url as URL in enumerator {
            let filePath = url.path
            if Safety.hasSymlinkComponent(filePath) {
                enumerator.skipDescendants()
                continue
            }
            guard !Safety.isCloudOrDataless(filePath) else { continue }
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  Int64(fileSize) >= minSize,
                  let identity = Safety.fileIdentity(at: filePath)
            else { continue }
            results.append(Candidate(path: filePath, size: Int64(fileSize), identity: identity))
        }
        return results
    }

    /// Hashes a chunk stream.
    ///
    /// A read that fails returns nil rather than the hash of the bytes read so
    /// far: a file that could not be read in full must never be treated as a
    /// duplicate of another file that merely shares its prefix.
    static func hashStream(_ next: () throws -> Data?) -> Data? {
        var hasher = SHA256()
        while true {
            let chunk: Data?
            do {
                chunk = try next()
            } catch {
                return nil
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize())
    }

    /// SHA-256 over the file contents. An unreadable file returns nil and is
    /// dropped from the comparison rather than being guessed at.
    static func contentHash(of path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return hashStream { try handle.read(upToCount: chunkSize) }
    }

    // MARK: - Hashing

    /// Hashes only the files that could possibly have a duplicate.
    ///
    /// Reading every multi-megabyte file in a home folder would take minutes;
    /// a file whose size is unique in the scan cannot be a duplicate at all, so
    /// it is skipped without being read. One path per inode is kept first —
    /// hard links share bytes and can never free space.
    static func hashCandidates(_ candidates: [Candidate], announce: Bool = false) -> [DupesCandidate] {
        var seenIdentities: Set<FileIdentity> = []
        let unique = candidates.filter { seenIdentities.insert($0.identity).inserted }

        var bySize: [Int64: [Candidate]] = [:]
        for candidate in unique {
            bySize[candidate.size, default: []].append(candidate)
        }
        let toHash = bySize.values.filter { $0.count >= 2 }.flatMap { $0 }

        var results: [DupesCandidate] = []
        results.reserveCapacity(toHash.count)
        for (index, candidate) in toHash.enumerated() {
            if announce, index % 100 == 0 {
                Term.err(Term.dim("  hashing \(index + 1)/\(toHash.count) …\r"))
            }
            results.append(
                DupesCandidate(
                    path: candidate.path,
                    size: candidate.size,
                    identity: candidate.identity,
                    hash: contentHash(of: candidate.path)
                )
            )
        }
        if announce, !toHash.isEmpty {
            Term.err(String(repeating: " ", count: 32) + "\r")
        }
        return results
    }

    // MARK: - Grouping

    struct DupesCandidate {
        let path: String
        let size: Int64
        let identity: FileIdentity
        let hash: Data?
    }

    struct DupesGroup {
        let size: Int64
        let paths: [String]

        var wastedBytes: Int64 {
            let extra = Int64(max(0, paths.count - 1))
            let (product, overflow) = size.multipliedReportingOverflow(by: extra)
            return overflow ? Int64.max : product
        }
    }

    /// Groups candidates by content, keeping only groups with more than one
    /// distinct file. Hard links collapse first: two paths to one inode free
    /// nothing when one is removed, so counting them would inflate the total.
    static func group(_ candidates: [DupesCandidate], minGroup: Int = 2) -> [DupesGroup] {
        var seenIdentities: Set<FileIdentity> = []
        var byKey: [String: (size: Int64, paths: [String])] = [:]

        for candidate in candidates {
            guard let hash = candidate.hash else { continue }
            guard seenIdentities.insert(candidate.identity).inserted else { continue }
            let key = "\(candidate.size):\(hash.base64EncodedString())"
            var bucket = byKey[key] ?? (size: candidate.size, paths: [])
            bucket.paths.append(candidate.path)
            byKey[key] = bucket
        }

        return byKey.values
            .filter { $0.paths.count >= minGroup }
            .map { DupesGroup(size: $0.size, paths: $0.paths.sorted()) }
            .sorted { left, right in
                if left.wastedBytes != right.wastedBytes { return left.wastedBytes > right.wastedBytes }
                return (left.paths.first ?? "") < (right.paths.first ?? "")
            }
    }

    // MARK: - JSON

    private func report(_ groups: [DupesGroup]) throws -> String {
        struct Out: Encodable {
            struct Group: Encodable {
                let sizeBytes: Int64
                let wastedBytes: Int64
                let count: Int
                let paths: [String]
            }
            let groups: [Group]
            let totalWastedBytes: Int64
        }
        let out = Out(
            groups: groups.map { Out.Group(
                sizeBytes: $0.size,
                wastedBytes: $0.wastedBytes,
                count: $0.paths.count,
                paths: $0.paths
            ) },
            totalWastedBytes: groups.reduce(Int64(0)) { $0 + $1.wastedBytes }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(out), as: UTF8.self)
    }
}
