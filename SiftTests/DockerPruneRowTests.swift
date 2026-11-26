import XCTest
@testable import Sift

/// The Docker prune row is virtual (empty path): the only way to keep it
/// retryable is to leave it out of `cleanedPaths` when the prune failed.
final class DockerPruneRowTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = fileManager.temporaryDirectory
            .appendingPathComponent("DockerPruneRow-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture { try? fileManager.removeItem(at: fixture) }
    }

    func testFailedPruneKeepsTheRowSoItCanBeRetried() async throws {
        let engine = CleaningEngine(dockerBinaryPaths: [try makeDockerScript(exitStatus: 7).path])
        let item = dockerItem()

        let result = await engine.cleanItems([item]) { _ in }

        XCTAssertFalse(result.errors.isEmpty, "A failed prune has to be reported")
        XCTAssertFalse(
            result.cleanedPaths.contains(item.path),
            "A failed prune must leave the Docker row in place for a retry"
        )
        XCTAssertEqual(result.itemsCleaned, 0)
    }

    // MARK: - Helpers

    private func dockerItem() -> CleanableItem {
        CleanableItem(
            name: "Docker prune",
            path: "",
            size: 4_096,
            category: .dockerCache,
            isSelected: true,
            lastModified: nil
        )
    }

    private func makeDockerScript(exitStatus: Int) throws -> URL {
        let script = fixture.appendingPathComponent("docker-\(UUID().uuidString)")
        let body = """
        #!/bin/sh
        echo 'Cannot connect to the Docker daemon' >&2
        exit \(exitStatus)
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}