import Darwin
import Foundation
import XCTest
@testable import sift

/// `purge` must only offer a folder whose name looks like build output when the
/// project file that produces it sits next to it. A source folder is allowed to
/// be called `target` or `node_modules` too.
final class PurgeMarkerTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        let provisional = fileManager.temporaryDirectory
            .appendingPathComponent("sift-purge-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: provisional, withIntermediateDirectories: true)
        var canonical = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard realpath(provisional.path, &canonical) != nil else {
            throw XCTSkip("temporary directory has no canonical path")
        }
        root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testTargetIsOnlyPurgedNextToItsOwnProjectFile() throws {
        let plain = try makeProject("plain-project")
        let rust = try makeProject("rust-project")
        let sourceFolder = try addArtifact(named: "target", to: plain)
        let buildFolder = try addArtifact(named: "target", to: rust)
        try writeMarker("Cargo.toml", in: rust)

        let scan = Purger.scan(roots: [root.path], olderThanDays: 0, ignore: try makeIgnoreStore())

        XCTAssertEqual(
            scan.groups.flatMap(\.items).map(\.path),
            [buildFolder.path],
            "only the target next to Cargo.toml is build output; \(sourceFolder.lastPathComponent) is a source folder here"
        )
    }

    private func makeProject(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func addArtifact(named name: String, to project: URL) throws -> URL {
        let url = project.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(repeating: 0x7F, count: 4096).write(to: url.appendingPathComponent("payload.bin"))
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)],
            ofItemAtPath: url.path
        )
        return url
    }

    private func writeMarker(_ name: String, in project: URL) throws {
        try Data("marker".utf8).write(to: project.appendingPathComponent(name))
    }

    private func makeIgnoreStore() throws -> IgnoreStore {
        try IgnoreStore(fileURL: root.appendingPathComponent("config/ignore"))
    }
}