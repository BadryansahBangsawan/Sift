import Foundation
import XCTest
@testable import Sift

final class AppleIntelligenceTests: XCTestCase {
    private final class FakeAssets: AppleAssetServicing {
        var available = true
        var assetTypes: [String: String] = Dictionary(
            uniqueKeysWithValues: AppleIntelligenceCatalog.modelSets.map { ($0.name, $0.assetType) })
        /// Bytes by asset type; nil means the service does not answer.
        var bytesByType: [String: Int64]? = [:]
        var resetCalls: [[String]] = []
        var resetResult: AppleAssetResetOutcome = .done

        var isAvailable: Bool { available }

        func assetType(for set: String) -> String? { assetTypes[set] }

        func inventory() -> [String: Int64]? { bytesByType }

        func downloadedBytes(for set: String) -> Int64? {
            guard let bytesByType else { return nil }
            guard let type = assetTypes[set] else { return nil }
            return bytesByType[type] ?? 0
        }

        func reset(sets: [String]) -> AppleAssetResetOutcome {
            resetCalls.append(sets)
            return resetResult
        }
    }

    private final class FakePreferences: ApplePreferenceStoring {
        var values: [String: ApplePreferenceValue] = [:]
        var forced: Set<String> = []

        private func key(_ domain: String, _ key: String) -> String { "\(domain):\(key)" }

        func read(domain: String, key: String) -> ApplePreferenceValue? {
            values[self.key(domain, key)]
        }

        func userValue(domain: String, key: String) -> ApplePreferenceValue? {
            values[self.key(domain, key)]
        }

        func isForced(domain: String, key: String) -> Bool {
            forced.contains(self.key(domain, key))
        }

        func write(_ value: ApplePreferenceValue?, domain: String, key: String) {
            if let value {
                values[self.key(domain, key)] = value
            } else {
                values[self.key(domain, key)] = nil
            }
        }
    }

    private final class FakeProfiles: AppleProfileWriting {
        var written: Data?
        var opened: URL?
        var failure: Error?

        func write(_ data: Data) throws -> URL {
            if let failure { throw failure }
            written = data
            return URL(fileURLWithPath: "/tmp/Sift-AppleIntelligence.mobileconfig")
        }

        func open(_ url: URL) { opened = url }
    }

    private func version(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    private func makeService(
        version: (Int, Int) = (26, 0),
        assets: FakeAssets = FakeAssets(),
        preferences: FakePreferences = FakePreferences(),
        profiles: FakeProfiles = FakeProfiles(),
        directory: URL? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> (AppleIntelligenceService, FakeAssets, FakePreferences, FakeProfiles, URL) {
        let folder = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-apple-ai-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let service = AppleIntelligenceService(
            assets: assets,
            preferences: preferences,
            profiles: profiles,
            journal: AppleTweakJournal(directory: folder),
            platform: ApplePlatform(
                version: self.version(version.0, version.1), isAppleSilicon: true),
            retryDelays: [],
            sleep: { _ in })
        return (service, assets, preferences, profiles, folder)
    }

    // MARK: plan

    func testPlanTurnsOffEveryAvailableFeatureAndRemovesEveryModelSet() throws {
        let (service, _, _, _, _) = makeService()
        let plan = service.plan(AppleIntelligenceSelection())

        let available = AppleIntelligenceCatalog.availableFeatures(on: version(26, 0))
        XCTAssertEqual(plan.featuresTurnedOff.map(\.id), available.map(\.id))
        XCTAssertEqual(
            plan.modelSets.map(\.name),
            AppleIntelligenceCatalog.setsToRemove(keeping: [], on: version(26, 0)))
        XCTAssertEqual(plan.profile?.keep, [])
        XCTAssertFalse(plan.isEmpty)
    }

    func testPlanKeepsAChosenFeatureAndOnlyTheModelsItNeeds() throws {
        let (service, _, _, _, _) = makeService()
        let plan = service.plan(AppleIntelligenceSelection(keep: ["writing-tools"]))

        XCTAssertFalse(plan.featuresTurnedOff.contains { $0.id == "writing-tools" })
        XCTAssertFalse(plan.modelSets.contains { $0.name == AppleIntelligenceCatalog.foundationModels })
        XCTAssertTrue(plan.modelSets.contains { $0.name == AppleIntelligenceCatalog.visualModels })
        XCTAssertEqual(plan.profile?.keep, ["writing-tools"])
    }

    func testUnsupportedMacOSPlansNothing() throws {
        let (service, _, _, _, _) = makeService(version: (15, 0))
        let status = service.status()
        let plan = service.plan(AppleIntelligenceSelection())

        XCTAssertFalse(status.supported)
        XCTAssertEqual(status.overall, .unavailable)
        XCTAssertTrue(plan.isEmpty)
    }

    func testMissingAssetServiceFallsBackToGuidance() throws {
        let assets = FakeAssets()
        assets.available = false
        let (service, _, _, _, _) = makeService(assets: assets)
        let status = service.status()
        let plan = service.plan(AppleIntelligenceSelection())

        XCTAssertFalse(status.supported)
        XCTAssertFalse(status.assetsAvailable)
        XCTAssertTrue(plan.isEmpty)
    }

    // MARK: profile

    func testProfileRestrictsTurnedOffFeaturesAndBlocksExactlyTheRemovedSets() throws {
        let (service, _, _, _, _) = makeService()
        let plan = service.plan(AppleIntelligenceSelection(keep: ["writing-tools"]))
        let contents = try XCTUnwrap(plan.profile)
        let data = try AppleIntelligenceProfile.data(contents, on: version(26, 0))
        let plist = try XCTUnwrap(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let payloads = try XCTUnwrap(plist["PayloadContent"] as? [[String: Any]])
        let restrictions = try XCTUnwrap(
            payloads.first { $0["PayloadType"] as? String == "com.apple.applicationaccess" })

        XCTAssertEqual(restrictions["allowAssistant"] as? Bool, false)
        XCTAssertEqual(restrictions["allowGenmoji"] as? Bool, false)
        XCTAssertNil(restrictions["allowWritingTools"], "a kept feature is left alone")

        let blocked = payloads.first {
            ($0["PayloadIdentifier"] as? String)?.hasSuffix(".com.apple.MobileAsset") == true
        }
        let blockContent = try XCTUnwrap(blocked?["PayloadContent"] as? [String: Any])
        let forced = try XCTUnwrap(blockContent["com.apple.MobileAsset"] as? [String: Any])
        let entries = try XCTUnwrap(forced["Forced"] as? [[String: Any]])
        let settings = try XCTUnwrap(entries.first?["mcx_preference_settings"] as? [String: String])

        XCTAssertEqual(settings.count, plan.modelSets.count)
        XCTAssertTrue(settings.values.allSatisfy { $0.hasPrefix("https://127.0.0.1:9/") })
        XCTAssertTrue(settings.keys.contains { $0.contains(AppleIntelligenceCatalog.visualModels) })
        XCTAssertFalse(settings.keys.contains { $0.contains(AppleIntelligenceCatalog.foundationModels) })
    }

    func testProfileIsMarkedStaleWhenThisMacOSHasMoreFeatures() throws {
        let all = Set(AppleIntelligenceCatalog.availableFeatures(on: version(26, 0)).map(\.id))
        let old = AppleIntelligenceProfile.Installed(
            on: true, ai: true, kept: [], tweaks: [], features: all.subtracting(["spatial-photos"]))

        XCTAssertTrue(old.isStale(on: version(26, 0)))
        XCTAssertFalse(
            AppleIntelligenceProfile.Installed(on: true, ai: true, features: all)
                .isStale(on: version(26, 0)))
    }

    // MARK: journal and undo

    func testApplyJournalsPreviousValueAndUndoRestoresIt() throws {
        let (service, _, preferences, _, _) = makeService()
        preferences.values["com.apple.WindowManager:EnableStandardClickToShowDesktop"] = .bool(true)
        let selection = AppleIntelligenceSelection(
            keep: Set(AppleIntelligenceCatalog.availableFeatures(on: version(26, 0)).map(\.id)),
            tweaks: ["click-to-desktop"])

        let result = service.apply(service.plan(selection))
        XCTAssertTrue(result.problems.isEmpty, result.problems.joined(separator: ", "))
        XCTAssertEqual(
            preferences.read(domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop"),
            .bool(false))

        let entries = try service.journal.load()
        XCTAssertEqual(
            entries["preference:com.apple.WindowManager:EnableStandardClickToShowDesktop"]?.previous,
            .bool(true))

        let undone = service.undo(.everything)
        XCTAssertTrue(undone.restored.contains("click-to-desktop"))
        XCTAssertEqual(
            preferences.read(domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop"),
            .bool(true))
        XCTAssertTrue(try service.journal.load().isEmpty)
    }

    func testUndoDeletesAKeyThatWasAbsent() throws {
        let (service, _, preferences, _, _) = makeService()
        let selection = AppleIntelligenceSelection(
            keep: Set(AppleIntelligenceCatalog.availableFeatures(on: version(26, 0)).map(\.id)),
            tweaks: ["desktop-widgets"])

        _ = service.apply(service.plan(selection))
        let entries = try service.journal.load()
        let entry = try XCTUnwrap(
            entries["preference:com.apple.WindowManager:StandardHideWidgets"])
        XCTAssertNil(entry.previous)
        XCTAssertEqual(
            preferences.read(domain: "com.apple.WindowManager", key: "StandardHideWidgets"),
            .bool(true))

        _ = service.undo(.everything)
        XCTAssertNil(
            preferences.read(domain: "com.apple.WindowManager", key: "StandardHideWidgets"))
    }

    func testTurningAppleIntelligenceOnOnlyAsksForProfileRemoval() throws {
        let (service, _, _, _, _) = makeService()
        let result = service.undo(.appleIntelligence)

        XCTAssertTrue(result.needsProfileRemoval)
        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertTrue(result.problems.isEmpty)
    }

    func testUnreadableJournalBlocksChanges() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-apple-ai-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try Data("garbage".utf8).write(to: folder.appendingPathComponent("apple-tweaks-journal.json"))
        let (service, _, preferences, _, _) = makeService(directory: folder)
        let selection = AppleIntelligenceSelection(
            keep: Set(AppleIntelligenceCatalog.availableFeatures(on: version(26, 0)).map(\.id)),
            tweaks: ["click-to-desktop"])

        let result = service.apply(service.plan(selection))

        XCTAssertFalse(result.problems.isEmpty)
        XCTAssertNil(
            preferences.read(domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop"))
    }

    // MARK: model removal

    func testAnEmptyModelResetIsRefused() throws {
        XCTAssertThrowsError(try AppleAssetReset.validate([]))

        let (service, assets, _, _, _) = makeService()
        let keepEverything = AppleIntelligenceSelection(
            keep: Set(AppleIntelligenceCatalog.availableFeatures(on: version(26, 0)).map(\.id)))
        let plan = service.plan(keepEverything)
        XCTAssertTrue(plan.modelSets.isEmpty)

        _ = service.apply(plan)
        XCTAssertTrue(assets.resetCalls.isEmpty, "the asset service must never be asked for an empty list")
    }

    func testApplyRemovesOneSetPerRequestAndReportsFailures() throws {
        let assets = FakeAssets()
        assets.resetResult = .done
        let (service, _, _, profiles, _) = makeService(assets: assets)
        let plan = service.plan(AppleIntelligenceSelection())

        let result = service.apply(plan)

        XCTAssertEqual(assets.resetCalls.count, plan.modelSets.count)
        XCTAssertTrue(assets.resetCalls.allSatisfy { $0.count == 1 })
        XCTAssertEqual(result.modelsRemoved.count, plan.modelSets.count)
        XCTAssertNotNil(profiles.written)
        XCTAssertEqual(profiles.opened?.lastPathComponent, "Sift-AppleIntelligence.mobileconfig")
    }

    func testSetWhoseAssetTypeDiffersIsLeftAlone() throws {
        let assets = FakeAssets()
        assets.assetTypes[AppleIntelligenceCatalog.spatialModels] = "com.apple.something.else"
        let (service, _, _, _, _) = makeService(assets: assets)
        let plan = service.plan(AppleIntelligenceSelection())
        XCTAssertTrue(plan.modelSets.contains { $0.name == AppleIntelligenceCatalog.spatialModels })

        let result = service.apply(plan)

        XCTAssertFalse(assets.resetCalls.contains([AppleIntelligenceCatalog.spatialModels]))
        XCTAssertFalse(result.modelProblems.isEmpty)
    }

    func testLockedSetIsRetriedAndThenReported() throws {
        let assets = FakeAssets()
        assets.resetResult = .locked
        let (service, _, _, _, _) = makeService(assets: assets)
        let plan = service.plan(AppleIntelligenceSelection())
        let result = service.apply(plan)

        XCTAssertEqual(assets.resetCalls.count, plan.modelSets.count)
        XCTAssertEqual(result.modelProblems.count, plan.modelSets.count)
    }
}
