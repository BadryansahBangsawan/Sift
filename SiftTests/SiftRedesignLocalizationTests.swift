import XCTest

/// Guards the Sift redesign strings: key screens keep their English keys, the
/// old app name is gone from every table, and the Services menu table matches
/// the NSMenuItem title in Info.plist.
final class SiftRedesignLocalizationTests: XCTestCase {
    private let redesignKeys = [
        "Where it sits",
        "Review and remove",
        "Empty Trash",
        "Empty the Trash?",
        "Biggest single wins",
        "Startup items",
        "Open Settings & reveal Sift",
        "Sift not in the list?",
        "Every %@",
        "Newest first",
        "Installers",
        "Brass",
    ]

    func testEnglishTableContainsRedesignKeys() throws {
        let english = try strings(language: "en", table: "Localizable")
        for key in redesignKeys {
            XCTAssertNotNil(english[key], "en.lproj/Localizable.strings is missing \"\(key)\"")
        }
    }

    func testNoTableMentionsTheOldAppName() throws {
        for language in try languages() {
            for table in ["Localizable", "InfoPlist", "ServicesMenu"] {
                let url = appSourceDirectory().appendingPathComponent("\(language).lproj/\(table).strings")
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let contents = try String(contentsOf: url, encoding: .utf8)
                XCTAssertFalse(contents.contains("PureMac"), "\(language).lproj/\(table).strings still mentions PureMac")
            }
        }
    }

    func testServicesMenuTablesMatchInfoPlistMenuTitle() throws {
        let infoURL = appSourceDirectory().appendingPathComponent("Info.plist")
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as? [String: Any]
        )
        let services = try XCTUnwrap(info["NSServices"] as? [[String: Any]])
        let menuItem = try XCTUnwrap(services.first?["NSMenuItem"] as? [String: String])
        let title = try XCTUnwrap(menuItem["default"])
        XCTAssertEqual(title, "Uninstall with Sift")

        for language in try languages() {
            let url = appSourceDirectory().appendingPathComponent("\(language).lproj/ServicesMenu.strings")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let table = try strings(language: language, table: "ServicesMenu")
            XCTAssertNotNil(table[title], "\(language).lproj/ServicesMenu.strings is missing \"\(title)\"")
        }
    }

    private func appSourceDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sift")
    }

    private func languages() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: appSourceDirectory().path)
            .filter { $0.hasSuffix(".lproj") }
            .map { String($0.dropLast(".lproj".count)) }
            .sorted()
    }

    private func strings(language: String, table: String) throws -> [String: String] {
        let url = appSourceDirectory().appendingPathComponent("\(language).lproj/\(table).strings")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(plist as? [String: String], "\(url.path) is not a strings table")
    }
}
