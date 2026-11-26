import XCTest
@testable import Sift

final class ProcessRunnerTests: XCTestCase {
    private let fileManager = FileManager.default
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = fileManager.temporaryDirectory
            .appendingPathComponent("ProcessRunner-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let fixture { try? fileManager.removeItem(at: fixture) }
    }

    func testFillsStderrBeforeStdoutWithoutDeadlocking() throws {
        let script = try makeScript("""
        #!/bin/sh
        yes x | head -c 1048576 >&2
        printf 'done'
        """)

        let started = Date()
        let result = ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path],
            timeout: 5
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "done")
        XCTAssertEqual(result.stderr.count, 1_048_576)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
    }

    func testKillsAChildThatIgnoresTerminationAndReportsTheTimeout() throws {
        let script = try makeScript("""
        #!/usr/bin/perl
        $| = 1;
        $SIG{TERM} = 'IGNORE';
        print 'started';
        sleep 10;
        """)

        let started = Date()
        let result = ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/perl"),
            arguments: [script.path],
            timeout: 0.3
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.status, -1)
        XCTAssertEqual(result.stdout, "started")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testPassesEnvironmentAndReturnsStatusAndStderr() throws {
        let script = try makeScript("""
        #!/bin/sh
        printf '%s' "$RUNNER_PROBE"
        printf 'boom' >&2
        exit 3
        """)

        let result = ProcessRunner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [script.path],
            timeout: 5,
            environment: ["RUNNER_PROBE": "value"]
        )

        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.stdout, "value")
        XCTAssertEqual(result.stderr, "boom")
    }

    private func makeScript(_ body: String) throws -> URL {
        let script = fixture.appendingPathComponent("child-\(UUID().uuidString)")
        try body.write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
