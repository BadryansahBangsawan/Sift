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

    func testAbsoluteXdgBeatsTheShellHome() {
        XCTAssertEqual(
            AppPaths.configBase(
                environment: ["XDG_CONFIG_HOME": "/srv/xdg/", "HOME": "/tmp/home"],
                loginHome: "/Users/real"
            ).path,
            "/srv/xdg"
        )
    }

    /// A value the sandbox cannot use is ignored, not resolved against `/`.
    func testRelativeValuesAreIgnored() {
        XCTAssertEqual(
            AppPaths.configBase(
                environment: ["XDG_CONFIG_HOME": "relative/xdg", "HOME": "relative/home"],
                loginHome: "/Users/real"
            ).path,
            "/Users/real/.config"
        )
    }

    func testEmptyValuesAreIgnored() {
        XCTAssertEqual(
            AppPaths.configBase(
                environment: ["XDG_CONFIG_HOME": "", "HOME": ""],
                loginHome: "/Users/real"
            ).path,
            "/Users/real/.config"
        )
    }

    /// The login home is the last resort when the shell exports neither.
    func testLoginHomeIsUsedWithoutAShellHome() {
        XCTAssertEqual(
            AppPaths.configBase(environment: [:], loginHome: "/Users/real").path,
            "/Users/real/.config"
        )
    }

    func testTrailingSlashAndSpacesSurvive() {
        XCTAssertEqual(
            AppPaths.configBase(
                environment: ["HOME": "/Volumes/Badry's SSD/home/"],
                loginHome: "/Users/real"
            ).path,
            "/Volumes/Badry's SSD/home/.config"
        )
    }
}
