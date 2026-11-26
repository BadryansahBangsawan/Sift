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

    func testEveryArtifactKindNeedsItsOwnProjectMarker() throws {
        let cases: [(artifact: String, marker: String)] = [
            ("node_modules", "package.json"),
            (".next", "package.json"),
            (".nuxt", "package.json"),
            (".turbo", "package.json"),
            (".svelte-kit", "package.json"),
            (".angular", "package.json"),
            (".parcel-cache", "package.json"),
            ("target", "Cargo.toml"),
            ("target", "pom.xml"),
            ("target", "build.sbt"),
            (".build", "Package.swift"),
            ("DerivedData", "Demo.xcodeproj"),
            ("DerivedData", "Demo.xcworkspace"),
            ("Pods", "Podfile"),
            (".gradle", "build.gradle"),
            (".gradle", "build.gradle.kts"),
            (".gradle", "settings.gradle"),
            (".gradle", "settings.gradle.kts"),
            (".tox", "tox.ini"),
            (".tox", "pyproject.toml"),
            (".venv", "pyproject.toml"),
            (".venv", "requirements.txt"),
            ("venv", "setup.py"),
            ("venv", "Pipfile"),
            ("__pycache__", "pyproject.toml"),
            (".pytest_cache", "setup.cfg"),
            ("cmake-build-debug", "CMakeLists.txt"),
        ]
        let ignore = try makeIgnoreStore()

        for (index, kind) in cases.enumerated() {
            let project = try makeProject("case-\(index)")
            let artifact = try addArtifact(named: kind.artifact, to: project)

            let withoutMarker = Purger.scan(roots: [project.path], olderThanDays: 0, ignore: ignore)
            XCTAssertTrue(
                withoutMarker.groups.isEmpty,
                "\(kind.artifact) without \(kind.marker) must not be offered"
            )

            try writeMarker(kind.marker, in: project)
            let withMarker = Purger.scan(roots: [project.path], olderThanDays: 0, ignore: ignore)
            XCTAssertEqual(
                withMarker.groups.flatMap(\.items).map(\.path),
                [artifact.path],
                "\(kind.artifact) next to \(kind.marker) must still be offered"
            )
        }
    }

    func testNestedProjectsCheckTheMarkerNextToEachArtifact() throws {
        let outer = try makeProject("outer")
        try writeMarker("package.json", in: outer)
        let outerModules = try addArtifact(named: "node_modules", to: outer)

        let inner = outer.appendingPathComponent("packages/desktop", isDirectory: true)
        try fileManager.createDirectory(at: inner, withIntermediateDirectories: true)
        try writeMarker("Cargo.toml", in: inner)
        let innerTarget = try addArtifact(named: "target", to: inner)

        let sourceOnly = inner.appendingPathComponent("src", isDirectory: true)
        try fileManager.createDirectory(at: sourceOnly, withIntermediateDirectories: true)
        _ = try addArtifact(named: "target", to: sourceOnly)

        let scan = Purger.scan(roots: [outer.path], olderThanDays: 0, ignore: try makeIgnoreStore())

        XCTAssertEqual(
            scan.groups.flatMap(\.items).map(\.path).sorted(),
            [outerModules.path, innerTarget.path].sorted()
        )
    }

    func testSymlinkedArtifactFolderIsNotOffered() throws {
        let project = try makeProject("linked")
        try writeMarker("Cargo.toml", in: project)
        let real = try addArtifact(named: "vendor/real-target", to: project)
        try fileManager.createSymbolicLink(
            atPath: project.appendingPathComponent("target").path,
            withDestinationPath: real.path
        )

        let scan = Purger.scan(roots: [project.path], olderThanDays: 0, ignore: try makeIgnoreStore())

        XCTAssertTrue(scan.groups.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: real.appendingPathComponent("payload.bin").path))
    }

    func testAFileNamedTargetIsNotAnArtifactFolder() throws {
        let project = try makeProject("file-target")
        try writeMarker("Cargo.toml", in: project)
        try Data(repeating: 0x11, count: 4096)
            .write(to: project.appendingPathComponent("target"))

        let scan = Purger.scan(roots: [project.path], olderThanDays: 0, ignore: try makeIgnoreStore())

        XCTAssertTrue(scan.groups.isEmpty)
    }

    func testIgnoredFileKeepsItsProjectArtifactOutOfTheScan() throws {
        let project = try makeProject("ignored")
        try writeMarker("Cargo.toml", in: project)
        let artifact = try addArtifact(named: "target", to: project)
        let keep = artifact.appendingPathComponent("keep.bin")
        try Data(repeating: 0x22, count: 4096).write(to: keep)
        var ignore = try makeIgnoreStore()
        _ = try ignore.add(keep.path)

        let scan = Purger.scan(roots: [project.path], olderThanDays: 0, ignore: ignore)

        XCTAssertTrue(scan.groups.isEmpty)
        XCTAssertTrue(fileManager.fileExists(atPath: keep.path))
    }

    private func makeProject(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func addArtifact(named name: String, to project: URL) throws -> URL {
        let url = project.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        if name != "__pycache__" {
            try Data(repeating: 0x7F, count: 4096).write(to: url.appendingPathComponent("payload.bin"))
        }
        try addSignature(for: name, to: url)
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)],
            ofItemAtPath: url.path
        )
        return url
    }

    /// Content evidence `purge` now requires before offering the folder.
    private func addSignature(for name: String, to url: URL) throws {
        let fileManager = FileManager.default
        func write(_ relative: String) throws {
            let target = url.appendingPathComponent(relative)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("generated".utf8).write(to: target)
        }
        switch name {
        case "node_modules":
            try write("pkg/package.json")
        case ".next":
            try write("BUILD_ID")
        case "target":
            try write(".rustc_info.json")
        case ".build":
            try write(".lock")
        case "DerivedData":
            try write("info.plist")
        case "Pods":
            try write("Manifest.lock")
        case ".gradle":
            try write("buildOutputCleanup/marker")
        case ".venv", "venv":
            try write("pyvenv.cfg")
        case "__pycache__":
            try write("module.pyc")
        case ".pytest_cache", ".mypy_cache", ".ruff_cache":
            try write("CACHEDIR.TAG")
        case ".tox":
            try write("env/pyvenv.cfg")
        case let name where name.hasPrefix("cmake-build"):
            try write("CMakeCache.txt")
        default:
            break
        }
    }

    private func writeMarker(_ name: String, in project: URL) throws {
        let url = project.appendingPathComponent(name)
        if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try Data("marker".utf8).write(to: url)
        }
    }

    private func makeIgnoreStore() throws -> IgnoreStore {
        try IgnoreStore(fileURL: root.appendingPathComponent("config/ignore"))
    }
}