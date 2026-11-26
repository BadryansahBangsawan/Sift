import XCTest

/// Sparkle reads its configuration from Info.plist and the package wiring
/// from the project file; both are part of the update feature.
final class UpdateConfigurationTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testInfoPlistDeclaresTheSparkleFeedKeyAndAutomaticChecks() throws {
        let plist = try loadPlist("Sift/Info.plist")

        XCTAssertEqual(
            plist["SUFeedURL"] as? String,
            "https://github.com/BadryansahBangsawan/Sift/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            plist["SUPublicEDKey"] as? String,
            "SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER",
            "Release builds replace the placeholder only after the owner generates a key"
        )
        XCTAssertEqual(plist["SUEnableAutomaticChecks"] as? Bool, true)
    }

    func testProjectLinksTheExactSparklePackageAndLetsXcodeEmbedIt() throws {
        let project = try String(
            contentsOf: repoRoot.appendingPathComponent("Sift.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )

        XCTAssertTrue(project.contains("XCRemoteSwiftPackageReference \"Sparkle\""))
        XCTAssertTrue(project.contains("repositoryURL = \"https://github.com/sparkle-project/Sparkle\";"))
        XCTAssertTrue(project.contains("kind = exactVersion;"))
        XCTAssertTrue(project.contains("version = 2.10.1;"))
        XCTAssertTrue(project.contains("productName = Sparkle;"))
        XCTAssertTrue(
            project.contains("Sparkle in Frameworks"),
            "The app target must link the Sparkle package product"
        )
        XCTAssertFalse(
            project.contains("Sparkle in Embed Frameworks"),
            "Xcode embeds a package's dynamic framework itself; a package product in a Copy Files phase is copied from BUILT_PRODUCTS_DIR/<product>, which does not exist"
        )
    }

    // MARK: - Helpers

    private func loadPlist(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(relativePath))
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(propertyList as? [String: Any])
    }
}