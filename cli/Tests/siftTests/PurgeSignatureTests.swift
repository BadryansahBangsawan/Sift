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

    // MARK: - Fixtures

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