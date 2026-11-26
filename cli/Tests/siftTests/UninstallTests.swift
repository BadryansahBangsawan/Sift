import Foundation
import XCTest
@testable import sift

final class UninstallTests: XCTestCase {
    func testOnlyExactBundleIdentifierNamesMatch() {
        let candidates = [
            "/Users/x/Library/Preferences/com.example.app.plist",
            "/Users/x/Library/Caches/com.example.app",
            "/Users/x/Library/Application Support/com.example.app",
            "/Users/x/Library/Caches/com.example.app.helper",
            "/Users/x/Library/Caches/com.example.application",
            "/Users/x/Library/Caches/Com.Example.App",
        ]

        XCTAssertEqual(
            Uninstall.matches(for: "com.example.app", candidates: candidates),
            [
                "/Users/x/Library/Preferences/com.example.app.plist",
                "/Users/x/Library/Caches/com.example.app",
                "/Users/x/Library/Application Support/com.example.app",
                "/Users/x/Library/Caches/Com.Example.App",
            ]
        )
    }

    func testSimilarNamesAreNeverMatched() {
        XCTAssertTrue(Uninstall.matches(for: "com.example.app", candidates: [
            "/Users/x/Library/Caches/com.example.app2",
            "/Users/x/Library/Caches/com.example",
            "/Users/x/Library/Caches/com.other.app",
        ]).isEmpty)
    }

    func testBundleIdentifierIsReadFromInfoPlist() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Example.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try plist(identifier: "com.example.app").write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertEqual(try Uninstall.bundleIdentifier(ofAppAt: app.path), "com.example.app")
    }

    func testMissingOrBlankIdentifierIsRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        XCTAssertThrowsError(try Uninstall.bundleIdentifier(ofAppAt: app.path))

        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try plist(identifier: "   ").write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertThrowsError(try Uninstall.bundleIdentifier(ofAppAt: app.path))
    }

    func testValidateRejectsRelativeAndNonBundlePaths() {
        XCTAssertThrowsError(try Uninstall.parse(["relative/App.app"]).validate())
        XCTAssertThrowsError(try Uninstall.parse(["/tmp/notbundle"]).validate())
    }

    func testScanListsBundleAndLeftoversUnselected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let leftover = directory.appendingPathComponent("com.example.app")
        try Data(repeating: 0x0, count: 128).write(to: leftover)

        let scan = Uninstall.scan(appPath: app.path, bundleID: "com.example.app", leftovers: [leftover.path])
        XCTAssertEqual(scan.groups.count, 2)
        XCTAssertEqual(scan.groups[0].tool, "Application")
        XCTAssertEqual(scan.groups[0].items.map(\.path), [app.path])
        XCTAssertEqual(scan.groups[1].items.map(\.path), [leftover.path])
        XCTAssertTrue(scan.groups.flatMap(\.items).allSatisfy { !$0.selected })
        // Sizes come from the filesystem's allocated size, so only the fact
        // that the leftover was measured matters here.
        XCTAssertGreaterThan(scan.groups[1].items[0].sizeBytes, 0)
    }

    func testLeftoverPathsFindFilesUnderTheHomeLibrary() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let preferences = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let plistPath = preferences.appendingPathComponent("com.example.app.plist")
        let cachePath = caches.appendingPathComponent("com.example.app")
        try Data(repeating: 0x1, count: 32).write(to: plistPath)
        try Data(repeating: 0x2, count: 64).write(to: cachePath)

        let ignore = try IgnoreStore(
            fileURL: home.appendingPathComponent("ignore"),
            legacyFileURL: nil,
            currentDirectoryPath: home.path
        )
        let found = Uninstall.leftoverPaths(
            for: "com.example.app",
            home: home.path,
            ignore: ignore
        )

        XCTAssertEqual(found.sorted(), [plistPath.path, cachePath.path].sorted())
    }

    func testLeftoverPathsIncludeLaunchAgentsMatchedByLabel() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let agentPath = agents.appendingPathComponent("com.example.agent.plist")
        try launchAgent(label: "com.example.app").write(to: agentPath)
        try launchAgent(label: "com.other.app").write(to: agents.appendingPathComponent("com.other.agent.plist"))

        let ignore = try IgnoreStore(
            fileURL: home.appendingPathComponent("ignore"),
            legacyFileURL: nil,
            currentDirectoryPath: home.path
        )

        XCTAssertEqual(
            Uninstall.leftoverPaths(for: "com.example.app", home: home.path, ignore: ignore),
            [agentPath.path]
        )
    }

    func testLeftoverPathsListAnAgentOnceWhenNameAndLabelBothMatch() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let agentPath = agents.appendingPathComponent("com.example.app.plist")
        try launchAgent(label: "com.example.app").write(to: agentPath)

        let ignore = try IgnoreStore(
            fileURL: home.appendingPathComponent("ignore"),
            legacyFileURL: nil,
            currentDirectoryPath: home.path
        )
        XCTAssertEqual(
            Uninstall.leftoverPaths(for: "com.example.app", home: home.path, ignore: ignore),
            [agentPath.path]
        )
    }

    func testLeftoverPathsSkipIgnoredLaunchAgentsAndNonPlistFiles() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let ignoredAgent = agents.appendingPathComponent("com.example.agent.plist")
        try launchAgent(label: "com.example.app").write(to: ignoredAgent)
        try Data("Label com.example.app".utf8)
            .write(to: agents.appendingPathComponent("notes.txt"))

        let ignoreFile = home.appendingPathComponent("ignore")
        try Data((ignoredAgent.path + "\n").utf8).write(to: ignoreFile)
        let ignore = try IgnoreStore(
            fileURL: ignoreFile,
            legacyFileURL: nil,
            currentDirectoryPath: home.path
        )
        XCTAssertEqual(Uninstall.leftoverPaths(for: "com.example.app", home: home.path, ignore: ignore), [])
    }

    func testLeftoverPathsSkipSymlinksAndIgnoredPaths() throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }

        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        let realTarget = home.appendingPathComponent("com.example.app.real")
        try Data(repeating: 0x3, count: 16).write(to: realTarget)
        try FileManager.default.createSymbolicLink(
            atPath: caches.appendingPathComponent("com.example.app").path,
            withDestinationPath: realTarget.path
        )

        let ignoredPath = logs.appendingPathComponent("com.example.app")
        try Data(repeating: 0x4, count: 16).write(to: ignoredPath)
        let ignoreFile = home.appendingPathComponent("ignore")
        try Data((ignoredPath.path + "\n").utf8).write(to: ignoreFile)

        let ignore = try IgnoreStore(
            fileURL: ignoreFile,
            legacyFileURL: nil,
            currentDirectoryPath: home.path
        )
        XCTAssertEqual(Uninstall.leftoverPaths(for: "com.example.app", home: home.path, ignore: ignore), [])
    }

    func testLeftoverPathsHandleSpacesAndUnicodeInTheHomePath() throws {
        let parent = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let home = parent.appendingPathComponent("fixture home ✓", isDirectory: true)
        let applicationSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: applicationSupport, withIntermediateDirectories: true)
        let leftover = applicationSupport.appendingPathComponent("com.example.app")
        try Data(repeating: 0x5, count: 16).write(to: leftover)

        let ignore = try IgnoreStore(
            fileURL: home.appendingPathComponent("ignore"),
            legacyFileURL: nil,
            currentDirectoryPath: home.path
        )
        XCTAssertEqual(
            Uninstall.leftoverPaths(for: "com.example.app", home: home.path, ignore: ignore),
            [leftover.path]
        )
    }

    func testRunningAppIsFoundWhenItsPathHasRegexCharacters() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Foo (Beta).app", isDirectory: true)
        let process = try launchSleep(in: app)

        XCTAssertEqual(try Uninstall.runningProcessID(forAppAt: app.path), Int(process.processIdentifier))
    }

    func testRunningAppLookupTreatsThePathLiterally() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        _ = try launchSleep(in: directory.appendingPathComponent("FooXBar.app", isDirectory: true))

        // A regex would let "." match the X; a literal comparison must not
        // report this other bundle as running.
        let lookalike = directory.appendingPathComponent("Foo.Bar.app", isDirectory: true)
        XCTAssertNil(try Uninstall.runningProcessID(forAppAt: lookalike.path))
    }

    func testPathInAnotherProcessArgumentsIsNotTheAppRunning() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Quiet.app", isDirectory: true)

        // The bundle path is an argument of this process, not its executable:
        // a command line scan would call that "running".
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        process.arguments = [app.path + "/"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        addTeardownBlock {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        XCTAssertNil(try Uninstall.runningProcessID(forAppAt: app.path))
    }

    func testRunningAppIsNoLongerReportedAfterItQuits() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let app = directory.appendingPathComponent("Quiet.app", isDirectory: true)
        let process = try launchSleep(in: app)
        XCTAssertEqual(try Uninstall.runningProcessID(forAppAt: app.path), Int(process.processIdentifier))

        process.terminate()
        process.waitUntilExit()

        XCTAssertNil(try Uninstall.runningProcessID(forAppAt: app.path))
    }

    /// Copies the system's sleep into the bundle and starts it, so the test
    /// looks at a real process whose executable path is inside the app.
    private func launchSleep(in app: URL, seconds: Int = 60) throws -> Process {
        let executable = app.appendingPathComponent(
            "Contents/MacOS/\(app.deletingPathExtension().lastPathComponent)"
        )
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: executable)
        // A copied platform binary is killed on Apple silicon until it is
        // signed again; an ad-hoc signature keeps it runnable.
        let signature = Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", executable.path])
        XCTAssertEqual(signature.status, 0, signature.err)

        let process = Process()
        process.executableURL = executable
        process.arguments = [String(seconds)]
        try process.run()
        addTeardownBlock {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        return process
    }

    private func launchAgent(label: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(label)</string>
        </dict></plist>
        """.utf8)
    }

    private func plist(identifier: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(identifier)</string>
        </dict></plist>
        """.utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-uninstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
