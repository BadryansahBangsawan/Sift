import CryptoKit
import Foundation
import XCTest
@testable import sift

final class DupesTests: XCTestCase {
    func testIdenticalContentsFormOneGroup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data(repeating: 0x41, count: 32)
        var candidates: [Dupes.DupesCandidate] = []
        for name in ["a.bin", "b.bin", "c.bin"] {
            let url = directory.appendingPathComponent(name)
            try payload.write(to: url)
            candidates.append(try candidate(for: url))
        }
        let unique = directory.appendingPathComponent("unique.bin")
        try Data(repeating: 0x42, count: 32).write(to: unique)
        candidates.append(try candidate(for: unique))

        let groups = Dupes.group(candidates)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.paths.count, 3)
        XCTAssertEqual(groups.first?.size, 32)
        XCTAssertEqual(groups.first?.wastedBytes, 64)
    }

    func testHardLinksAreCountedOnce() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let payload = Data(repeating: 0x43, count: 64)
        let original = directory.appendingPathComponent("original.bin")
        try payload.write(to: original)
        let linked = directory.appendingPathComponent("linked.bin")
        XCTAssertEqual(link(original.path, linked.path), 0, "hard link should succeed")

        let groups = Dupes.group([try candidate(for: original), try candidate(for: linked)])
        XCTAssertTrue(groups.isEmpty, "one inode is not a duplicate pair")
    }

    func testOneCopyIsNotAGroupButTwoAre() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let single = directory.appendingPathComponent("single.bin")
        try Data(repeating: 0x44, count: 16).write(to: single)
        XCTAssertTrue(Dupes.group([try candidate(for: single)]).isEmpty)

        let twin = directory.appendingPathComponent("twin.bin")
        try Data(repeating: 0x44, count: 16).write(to: twin)
        let groups = Dupes.group([try candidate(for: single), try candidate(for: twin)])
        XCTAssertEqual(groups.first?.size, 16)
        XCTAssertEqual(groups.first?.wastedBytes, 16)
    }

    func testTildePathsAreExpandedLikeOtherCommands() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertNoThrow(try Dupes.parse(["~"]).validate(), "~ must mean the home folder")
        XCTAssertNoThrow(try Dupes.parse(["~/Library"]).validate(), "~/ must expand before the check")
        XCTAssertNoThrow(try Dupes.parse([home]).validate())
    }

    func testDupesStillRejectsRelativeAndMissingPaths() {
        XCTAssertThrowsError(try Dupes.parse(["relative/folder"]).validate(), "relative paths stay rejected")
        XCTAssertThrowsError(
            try Dupes.parse(["~/definitely-missing-\(UUID().uuidString)"]).validate(),
            "expansion must not make a missing folder pass"
        )
    }

    /// A file that fails part-way through must not be hashed from its prefix:
    /// two files with the same size and a shared prefix would otherwise be
    /// reported as duplicates and one of them offered for removal.
    func testHashStreamReturnsNilWhenAReadFails() {
        var reads = 0
        let hash = Dupes.hashStream {
            reads += 1
            if reads == 1 { return Data(repeating: 0xAB, count: 64) }
            throw CocoaError(.fileReadUnknown)
        }
        XCTAssertNil(hash, "an incomplete read must not produce a hash")
    }

    func testHashStreamMatchesTheWholeContent() {
        let chunks = [
            Data(repeating: 0x01, count: 32),
            Data(repeating: 0x02, count: 32),
            Data(),
        ]
        var index = 0
        let hash = Dupes.hashStream {
            defer { index += 1 }
            return chunks[index]
        }

        let expected = SHA256.hash(data: chunks.dropLast().reduce(into: Data()) { $0.append($1) })
        XCTAssertEqual(hash, Data(expected))
    }

    func testHashStreamOfEmptyContentIsTheEmptyHash() {
        let hash = Dupes.hashStream { Data() }
        XCTAssertEqual(hash, Data(SHA256.hash(data: Data())))
    }

    /// Two files that share the first chunk but differ after it are not
    /// duplicates. This is the shape a prefix hash would have collapsed.
    func testSharedPrefixBeyondTheFirstChunkIsNotADuplicate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let prefix = Data(repeating: 0x5A, count: 1_048_576)
        let first = directory.appendingPathComponent("first.bin")
        let second = directory.appendingPathComponent("second.bin")
        try (prefix + Data(repeating: 0x01, count: 4_096)).write(to: first)
        try (prefix + Data(repeating: 0x02, count: 4_096)).write(to: second)

        let hashed = Dupes.hashCandidates([
            Dupes.Candidate(path: first.path, size: 1_052_672, identity: FileIdentity(device: 1, inode: 11)),
            Dupes.Candidate(path: second.path, size: 1_052_672, identity: FileIdentity(device: 1, inode: 12)),
        ])

        XCTAssertEqual(hashed.compactMap(\.hash).count, 2)
        XCTAssertNotEqual(hashed[0].hash, hashed[1].hash)
        XCTAssertTrue(Dupes.group(hashed).isEmpty)
    }

    func testEmptyFilesStillCompareByContent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let one = directory.appendingPathComponent("one.bin")
        let two = directory.appendingPathComponent("two.bin")
        try Data().write(to: one)
        try Data().write(to: two)

        let groups = Dupes.group([try candidate(for: one), try candidate(for: two)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.wastedBytes, 0)
    }

    func testUnreadableFilesAreSkipped() {
        let identity = FileIdentity(device: 1, inode: 2)
        let groups = Dupes.group([
            Dupes.DupesCandidate(path: "/nope/a", size: 10, identity: identity, hash: nil),
            Dupes.DupesCandidate(path: "/nope/b", size: 10, identity: FileIdentity(device: 1, inode: 3), hash: nil),
        ])
        XCTAssertTrue(groups.isEmpty)
    }

    func testGroupsAreSortedByWastedBytesDescending() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var candidates: [Dupes.DupesCandidate] = []
        for name in ["big1", "big2"] {
            let url = directory.appendingPathComponent(name)
            try Data(repeating: 0x45, count: 2_000).write(to: url)
            candidates.append(try candidate(for: url))
        }
        for name in ["small1", "small2"] {
            let url = directory.appendingPathComponent(name)
            try Data(repeating: 0x46, count: 100).write(to: url)
            candidates.append(try candidate(for: url))
        }

        let groups = Dupes.group(candidates)
        XCTAssertEqual(groups.map(\.wastedBytes), [2_000, 100])
    }

    func testValidateRejectsRelativeAndMissingPaths() throws {
        XCTAssertThrowsError(try Dupes.parse(["relative/path"]).validate())
        XCTAssertThrowsError(try Dupes.parse(["/definitely/not/here/at/all"]).validate())
        XCTAssertNoThrow(try Dupes.parse([]).validate())
    }

    private func candidate(for url: URL) throws -> Dupes.DupesCandidate {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        guard let identity = Safety.fileIdentity(at: url.path) else {
            throw XCTSkip("no file identity for \(url.path)")
        }
        return Dupes.DupesCandidate(
            path: url.path,
            size: size,
            identity: identity,
            hash: Dupes.contentHash(of: url.path)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-dupes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
