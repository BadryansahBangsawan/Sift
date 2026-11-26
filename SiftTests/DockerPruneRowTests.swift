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

    func testSuccessfulPruneClearsTheRowAndCountsReclaimedBytes() async throws {
        let script = try makeDockerScript(
            exitStatus: 0,
            stdoutLine: "Total reclaimed space: 2kB",
            stderrLine: nil
        )
        let item = dockerItem()

        let result = await CleaningEngine(dockerBinaryPaths: [script.path])
            .cleanItems([item]) { _ in }

        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.cleanedPaths.contains(item.path))
        XCTAssertEqual(result.freedSpace, 2_000)
        XCTAssertEqual(result.itemsCleaned, 1)
    }

    func testSuccessfulPruneWithNothingReclaimedStillClearsTheRow() async throws {
        let script = try makeDockerScript(
            exitStatus: 0,
            stdoutLine: "Total reclaimed space: 0B",
            stderrLine: nil
        )
        let item = dockerItem()

        let result = await CleaningEngine(dockerBinaryPaths: [script.path])
            .cleanItems([item]) { _ in }

        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertTrue(result.cleanedPaths.contains(item.path), "There is nothing left to retry")
        XCTAssertEqual(result.freedSpace, 0)
        XCTAssertEqual(result.itemsCleaned, 0)
    }

    func testMissingDockerCLIKeepsTheRow() async throws {
        let missing = fixture.appendingPathComponent("missing-docker").path
        let item = dockerItem()

        let result = await CleaningEngine(dockerBinaryPaths: [missing])
            .cleanItems([item]) { _ in }

        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertFalse(result.cleanedPaths.contains(item.path))
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

    private func makeDockerScript(
        exitStatus: Int,
        stdoutLine: String? = nil,
        stderrLine: String? = "Cannot connect to the Docker daemon"
    ) throws -> URL {
        let script = fixture.appendingPathComponent("docker-\(UUID().uuidString)")
        var body = "#!/bin/sh\n"
        if let stdoutLine {
            body += "printf '%s\\n' '\(stdoutLine)'\n"
        }
        if let stderrLine {
            body += "printf '%s\\n' '\(stderrLine)' >&2\n"
        }
        body += "exit \(exitStatus)\n"
        try body.write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}