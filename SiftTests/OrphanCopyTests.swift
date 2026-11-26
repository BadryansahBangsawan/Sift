import XCTest
@testable import Sift

/// The Leftovers page must say whether it never looked, could not compare, or
/// found nothing. Before the first scan it claimed "No Orphaned Files", which
/// reads as "your Mac is clean" when nothing had been checked.
@MainActor
final class OrphanCopyTests: XCTestCase {
    private static let keys = [
        "Not scanned yet",
        "Scan to see whether uninstalled apps left files behind.",
        "Couldn't compare installed apps",
        "Sift needs the list of installed apps before it can call a file a leftover. Try again in a moment.",
        "No Orphaned Files",
    ]

    func testTheLeftoversPageHasCopyForEveryState() throws {
        let files = try localizationFiles()
        XCTAssertFalse(files.isEmpty, "Expected Localizable.strings files in the app source")

        for (language, url) in files {
            let strings = try read(url)
            for key in Self.keys {
                let value = strings[key]
                XCTAssertNotNil(value, "\(language).lproj is missing \"\(key)\"")
                XCTAssertFalse(value?.isEmpty ?? true, "\(language).lproj has an empty \"\(key)\"")
            }
        }
    }

    func testAPageThatHasNotScannedDiffersFromOneThatFoundNothing() async throws {
        let state = await MainActor.run {
            AppState(performStartupTasks: false, installedAppsProvider: { [] })
        }
        let freshCompleted = state.orphanScanCompleted
        XCTAssertFalse(freshCompleted, "A page that has not scanned must not show the clean-Mac state")

        state.findOrphans()
        for _ in 0..<200 {
            if state.orphanScanCompleted { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let completed = state.orphanScanCompleted
        let needsList = state.orphanScanNeedsAppList
        XCTAssertTrue(completed, "A refused scan still counts as finished, so the page stops saying \"not scanned\"")
        XCTAssertTrue(needsList, "The page must blame the missing app list, not claim a clean Mac")
    }

    private func localizationFiles() throws -> [String: URL] {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSourceDirectory = sourceRoot.appendingPathComponent("Sift")
        let contents = try FileManager.default.contentsOfDirectory(
            at: appSourceDirectory,
            includingPropertiesForKeys: nil
        )

        return contents.reduce(into: [String: URL]()) { result, url in
            guard url.pathExtension == "lproj" else { return }
            let strings = url.appendingPathComponent("Localizable.strings")
            guard FileManager.default.fileExists(atPath: strings.path) else { return }
            result[url.deletingPathExtension().lastPathComponent] = strings
        }
    }

    private func read(_ url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return (plist as? [String: String]) ?? [:]
    }
}
