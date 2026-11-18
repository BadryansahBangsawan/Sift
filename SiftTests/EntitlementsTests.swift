import XCTest

/// Release builds enable the hardened runtime, which blocks Apple Events unless
/// the app declares the automation entitlement. Without it Finder's "empty
/// trash" script fails with -1743 before macOS can even ask for consent.
final class EntitlementsTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testHardenedRuntimeAllowsAppleEventsWithoutSandbox() throws {
        let url = repoRoot.appendingPathComponent("Sift/Sift.entitlements")
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(propertyList as? [String: Any])

        XCTAssertEqual(
            entitlements["com.apple.security.automation.apple-events"] as? Bool,
            true,
            "Signed builds can only send Apple Events (Finder empty trash) with the automation entitlement"
        )
        XCTAssertEqual(
            entitlements["com.apple.security.app-sandbox"] as? Bool,
            false,
            "The app must stay unsandboxed so it can scan the whole disk"
        )
    }
}
