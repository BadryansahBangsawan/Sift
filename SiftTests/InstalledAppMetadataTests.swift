import XCTest
@testable import Sift

final class InstalledAppMetadataTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstalledAppMetadataTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFetchAppReadsVersionAndCategoryFromInfoPlist() throws {
        let url = try makeFixtureApp(named: "Fixture", info: [
            "CFBundleIdentifier": "test.puremac.fixture.\(UUID().uuidString)",
            "CFBundleName": "Fixture",
            "CFBundleShortVersionString": "4.2.1",
            "LSApplicationCategoryType": "public.app-category.developer-tools",
        ])

        let app = try XCTUnwrap(AppInfoFetcher.shared.fetchApp(at: url))

        XCTAssertEqual(app.appName, "Fixture")
        XCTAssertEqual(app.version, "4.2.1")
        XCTAssertEqual(app.category, "developer")
    }

    func testFetchAppLeavesMetadataNilWhenInfoPlistOmitsIt() throws {
        let url = try makeFixtureApp(named: "Bare", info: [
            "CFBundleIdentifier": "test.puremac.bare.\(UUID().uuidString)",
        ])

        let app = try XCTUnwrap(AppInfoFetcher.shared.fetchApp(at: url))

        XCTAssertNil(app.version)
        XCTAssertNil(app.category)
    }

    private func makeFixtureApp(named name: String, info: [String: Any]) throws -> URL {
        let appURL = tempDir.appendingPathComponent("\(name).app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
    }
    func testKnownCategoryTypesMapToShortLabels() {
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.developer-tools"), "developer")
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.graphics-design"), "design")
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.productivity"), "productivity")
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.utilities"), "utility")
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.social-networking"), "communication")
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.business"), "business")
    }

    func testUnknownCategoryTypeFallsBackToStrippedSuffix() {
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.role-playing-games"), "role playing games")
        XCTAssertEqual(AppInfoFetcher.categoryLabel(for: "public.app-category.music"), "music")
    }

    func testMissingOrEmptyCategoryTypeHasNoLabel() {
        XCTAssertNil(AppInfoFetcher.categoryLabel(for: nil))
        XCTAssertNil(AppInfoFetcher.categoryLabel(for: ""))
        XCTAssertNil(AppInfoFetcher.categoryLabel(for: "public.app-category."))
    }
}
