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
}