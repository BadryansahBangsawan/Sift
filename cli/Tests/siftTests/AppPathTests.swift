import Foundation
import XCTest
@testable import sift

/// Where settings and the ignore list live.
///
/// XDG Base Directory says `XDG_CONFIG_HOME` defaults to `$HOME/.config`, so a
/// shell that sets `HOME` (a test harness, a sandbox, `HOME=/tmp/x sift-cli`)
/// must read and write that home's settings, not the login user's.
final class AppPathTests: XCTestCase {
    func testConfigBaseUsesAnAbsoluteXdgHome() {
        XCTAssertEqual(
            AppPaths.configBase(
                environment: ["XDG_CONFIG_HOME": "/tmp/xdg", "HOME": "/tmp/home"],
                loginHome: "/Users/real"
            ).path,
            "/tmp/xdg"
        )
    }

    func testConfigBaseFallsBackToTheShellHome() {
        XCTAssertEqual(
            AppPaths.configBase(
                environment: ["HOME": "/tmp/home"],
                loginHome: "/Users/real"
            ).path,
            "/tmp/home/.config"
        )
    }
}
