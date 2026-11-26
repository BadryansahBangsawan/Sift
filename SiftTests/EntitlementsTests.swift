import XCTest

/// Sift scans the whole disk and must stay unsandboxed. It no longer sends
/// Apple Events to other apps (the Finder Trash-emptying script is gone), so
/// it must not ask for the automation entitlement either.
final class EntitlementsTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testAppStaysUnsandboxedWithoutAppleEvents() throws {
        let url = repoRoot.appendingPathComponent("Sift/Sift.entitlements")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(propertyList as? [String: Any])

        XCTAssertNil(
            entitlements["com.apple.security.automation.apple-events"],
            "No code sends Apple Events any more, so the automation entitlement must stay off"
        )
        XCTAssertEqual(
            entitlements["com.apple.security.app-sandbox"] as? Bool,
            false,
            "The app must stay unsandboxed so it can scan the whole disk"
        )
    }
}
