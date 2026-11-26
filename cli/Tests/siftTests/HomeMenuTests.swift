import Darwin
import Foundation
import XCTest
@testable import sift

/// The interactive menu's Uninstall entry defaults to "/Applications", which is
/// not a bundle. Answering with Return must show a message and leave the
/// session running, not throw out of the whole menu.
final class HomeMenuTests: XCTestCase {
    func testDefaultUninstallAnswerKeepsTheMenuAlive() throws {
        let accepted = try HomeMenu.runUninstall("/Applications")

        XCTAssertFalse(accepted, "a non-bundle answer is not an uninstall")
    }

    func testDefaultUninstallAnswerPrintsAClearMessage() {
        var accepted = true
        let message = captureStandardError { accepted = HomeMenu.runUninstall("/Applications") }

        XCTAssertFalse(accepted)
        XCTAssertTrue(message.contains("Not an app bundle: /Applications"), message)
    }

    func testMissingAndRelativeAnswersReturnToTheMenu() {
        var accepted = true
        let missing = captureStandardError {
            accepted = HomeMenu.runUninstall("/tmp/No Such App-\(UUID().uuidString).app")
        }
        XCTAssertFalse(accepted)
        XCTAssertTrue(missing.contains("No such app"), missing)

        let relative = captureStandardError {
            accepted = HomeMenu.runUninstall("Applications/Example.app")
        }
        XCTAssertFalse(accepted)
        XCTAssertTrue(relative.contains("Path must be absolute"), relative)
    }

    private func captureStandardError(_ body: () -> Void) -> String {
        let pipe = Pipe()
        fflush(stderr)
        let saved = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        body()
        fflush(stderr)
        dup2(saved, STDERR_FILENO)
        close(saved)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}