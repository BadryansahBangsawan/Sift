import Foundation
import XCTest
@testable import sift

/// `purge` must require the same content evidence as the app: a folder with an
/// artifact name is only offered when its contents look generated.
final class PurgeSignatureTests: XCTestCase {
    private let fileManager = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory
            .appendingPathComponent("sift-purge-signature-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? fileManager.removeItem(at: root) }
        try super.tearDownWithError()
    }

    func testHandWrittenTargetNextToPomIsNotOffered() throws {
        let project = try makeProject("maven-source")
        try Data("<project/>".utf8).write(to: project.appendingPathComponent("pom.xml"))
        try writeFile("target/notes.md", in: project, bytes: 4_096)
        try ageArtifact("target", in: project)

        XCTAssertTrue(offered(in: project).isEmpty, "a hand-written target folder is not build output")
    }

    func testGeneratedTargetNextToPomIsStillOffered() throws {
        let project = try makeProject("maven-build")
        try Data("<project/>".utf8).write(to: project.appendingPathComponent("pom.xml"))
        try writeFile("target/classes/com/example/App.class", in: project, bytes: 4_096)
        try ageArtifact("target", in: project)

        XCTAssertEqual(offered(in: project), [canonical(project.appendingPathComponent("target").path)])
    }

    func testContentSignaturesCoverEveryOfferedArtifactName() throws {
        let cases: [(name: String, genuine: String, handmade: String?)] = [
            ("node_modules", "pkg/package.json", "notes.md"),
            (".next", "BUILD_ID", "notes.md"),
            (".nuxt", "generated.txt", nil),
            (".turbo", "generated.txt", nil),
            (".svelte-kit", "generated.txt", nil),
            (".angular", "generated.txt", nil),
            (".parcel-cache", "generated.txt", nil),
            ("target", ".rustc_info.json", "notes.md"),
            (".build", ".lock", "notes.md"),
            ("DerivedData", "info.plist", "notes.md"),
            ("Pods", "Manifest.lock", "notes.md"),
            (".gradle", "buildOutputCleanup/marker", "notes.md"),
            (".venv", "pyvenv.cfg", "notes.md"),
            ("venv", "pyvenv.cfg", "notes.md"),
            ("__pycache__", "module.pyc", "module.py"),
            (".pytest_cache", "CACHEDIR.TAG", "notes.md"),
            (".mypy_cache", "CACHEDIR.TAG", "notes.md"),
            (".ruff_cache", "CACHEDIR.TAG", "notes.md"),
            (".tox", "env/pyvenv.cfg", "notes.md"),
            ("cmake-build-debug", "CMakeCache.txt", "notes.md"),
        ]
        var covered = Set<String>()
        for (index, item) in cases.enumerated() {
            covered.insert(item.name)
            let genuine = try artifactFolder("case-\(index)", name: item.name)
            try writeFile("\(item.name)/\(item.genuine)", in: genuine, bytes: 32)
            XCTAssertTrue(
                Purger.hasContentSignature(for: item.name, in: genuine.appendingPathComponent(item.name)),
                "\(item.name) with \(item.genuine) must prove generated"
            )

            if let handmade = item.handmade {
                let folder = try artifactFolder("handmade-\(index)", name: item.name)
                try writeFile("\(item.name)/\(handmade)", in: folder, bytes: 32)
                XCTAssertFalse(
                    Purger.hasContentSignature(for: item.name, in: folder.appendingPathComponent(item.name)),
                    "\(item.name) with only \(handmade) must not be offered"
                )
            }
        }

        let offered = Purger.artifactNames.union(["cmake-build-debug"])
        XCTAssertEqual(covered, offered, "a rule changed without a signature test")
    }

    // MARK: - Fixtures

    private func artifactFolder(_ project: String, name: String) throws -> URL {
        let folder = try makeProject(project)
        try fileManager.createDirectory(
            at: folder.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )
        return folder
    }

    private func makeProject(_ name: String) throws -> URL {
        let project = root.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: project, withIntermediateDirectories: true)
        return project
    }

    private func writeFile(_ relative: String, in project: URL, bytes: Int) throws {
        let url = project.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    private func ageArtifact(_ name: String, in project: URL) throws {
        try fileManager.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -30 * 86_400)],
            ofItemAtPath: project.appendingPathComponent(name).path
        )
    }

    private func offered(in project: URL) -> [String] {
        guard let ignore = try? IgnoreStore(fileURL: root.appendingPathComponent("ignore")) else { return [] }
        return Purger.scan(roots: [project.path], olderThanDays: 0, ignore: ignore)
            .groups.flatMap(\.items).map(\.path)
    }

    private func canonical(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        if realpath(path, &buffer) != nil { return String(cString: buffer) }
        return path
    }
}