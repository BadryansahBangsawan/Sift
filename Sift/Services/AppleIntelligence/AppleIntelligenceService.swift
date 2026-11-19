import Foundation

/// Where a non-profile setting's previous value is kept so undo can put it back.
struct AppleTweakJournal {
    struct Entry: Codable, Equatable {
        var tweak: String
        var date: Date
        /// Nil means the key was absent before Sift wrote it, so undo deletes it.
        var previous: ApplePreferenceValue?
    }

    enum Failure: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let path):
                return String(
                    localized: "The undo journal at \(path) can't be read, so Sift changes nothing until it is moved or fixed.")
            }
        }
    }

    let directory: URL
    var url: URL { directory.appendingPathComponent("apple-tweaks-journal.json") }

    static let defaultDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Sift", isDirectory: true)

    static var shared: AppleTweakJournal { AppleTweakJournal(directory: defaultDirectory) }

    func load() throws -> [String: Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else {
            throw Failure.unreadable(url.path)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([String: Entry].self, from: data)
        } catch {
            throw Failure.unreadable(url.path)
        }
    }

    func save(_ entries: [String: Entry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(entries).write(to: url, options: .atomic)
    }
}

/// The Mac Sift is running on, as far as Apple Intelligence support goes.
struct ApplePlatform {
    var version: OperatingSystemVersion
    var isAppleSilicon: Bool

    var supportsAppleIntelligence: Bool {
        isAppleSilicon && (version.majorVersion, version.minorVersion) >= (15, 1)
    }

    static var current: ApplePlatform {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return ApplePlatform(
            version: ProcessInfo.processInfo.operatingSystemVersion,
            isAppleSilicon: machine == "arm64")
    }
}

enum AppleIntelligenceFeatureState: String, Equatable {
    case lockedOff, off, on, unknown

    var isOff: Bool { self == .lockedOff || self == .off }
}

enum AppleIntelligenceOverall: Equatable {
    case on, off, partlyOff, unavailable
}

struct AppleIntelligenceStatus {
    var platform: ApplePlatform
    var assetsAvailable: Bool
    var profile: AppleIntelligenceProfile.Installed
    var features: [String: AppleIntelligenceFeatureState]
    var modelBytes: [String: Int64]

    var supported: Bool { platform.supportsAppleIntelligence && assetsAvailable }

    var overall: AppleIntelligenceOverall {
        guard supported else { return .unavailable }
        let states = features.values
        if states.allSatisfy({ $0.isOff }) { return .off }
        if states.allSatisfy({ !$0.isOff }) { return .on }
        return .partlyOff
    }

    /// Bytes for a feature only when every set it needs answered.
    func bytes(for feature: AppleIntelligenceFeature) -> Int64? {
        var total: Int64 = 0
        for name in feature.modelSets {
            guard let bytes = modelBytes[name] else { return nil }
            total += bytes
        }
        return total
    }

    var totalModelBytes: Int64? {
        var total: Int64 = 0
        for set in AppleIntelligenceCatalog.availableModelSets(on: platform.version) {
            guard let bytes = modelBytes[set.name] else { return nil }
            total += bytes
        }
        return total
    }
}

struct AppleIntelligenceSelection: Equatable {
    /// Features left on. Everything else in the catalog is turned off.
    var keep: Set<String> = []
    /// Optional privacy and annoyance tweaks.
    var tweaks: Set<String> = []
}

struct AppleIntelligenceChange: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let isProfile: Bool
}

struct AppleIntelligencePlan: Identifiable {
    let id = UUID()
    var featuresTurnedOff: [AppleIntelligenceFeature] = []
    var tweaks: [AppleTweak] = []
    var modelSets: [AppleIntelligenceModelSet] = []
    var modelBytes: [String: Int64] = [:]
    var profile: AppleIntelligenceProfileContents?
    var changes: [AppleIntelligenceChange] = []

    var isEmpty: Bool {
        featuresTurnedOff.isEmpty && tweaks.isEmpty && modelSets.isEmpty && profile == nil
    }

    /// Only the sets whose size the service reported.
    var reportedModelBytes: Int64? {
        var total: Int64 = 0
        for set in modelSets {
            guard let bytes = modelBytes[set.name] else { return nil }
            total += bytes
        }
        return total
    }
}

struct AppleIntelligenceApplyResult {
    var profileURL: URL?
    var modelsRemoved: [String] = []
    var modelProblems: [String] = []
    var problems: [String] = []

    var succeeded: Bool { problems.isEmpty && modelProblems.isEmpty }
}

enum AppleIntelligenceUndoScope {
    /// Turning Apple Intelligence back on. The profile is in System Settings,
    /// so Sift can only tell the person which pane to open.
    case appleIntelligence
    /// Every setting Sift wrote outside the profile.
    case everything
}

struct AppleIntelligenceUndoResult {
    var restored: [String] = []
    var problems: [String] = []
    var needsProfileRemoval: Bool = false
}

/// One module for Apple Intelligence: read the state, plan the change, apply
/// it through injected adapters, and undo exactly what was journaled.
final class AppleIntelligenceService {
    let assets: AppleAssetServicing
    let preferences: ApplePreferenceStoring
    let profiles: AppleProfileWriting
    let journal: AppleTweakJournal
    let platform: ApplePlatform
    /// Waits between reset attempts while macOS reports a lock.
    let retryDelays: [TimeInterval]
    let sleep: (TimeInterval) -> Void

    init(
        assets: AppleAssetServicing = UAFAssetService(),
        preferences: ApplePreferenceStoring = CFPreferencesStore(),
        profiles: AppleProfileWriting = FinderProfileWriter(),
        journal: AppleTweakJournal = .shared,
        platform: ApplePlatform = .current,
        retryDelays: [TimeInterval] = [5, 15],
        sleep: @escaping (TimeInterval) -> Void = Thread.sleep
    ) {
        self.assets = assets
        self.preferences = preferences
        self.profiles = profiles
        self.journal = journal
        self.platform = platform
        self.retryDelays = retryDelays
        self.sleep = sleep
    }

    // MARK: status

    func status() -> AppleIntelligenceStatus {
        let version = platform.version
        let features = AppleIntelligenceCatalog.availableFeatures(on: version)
        var bytes: [String: Int64] = [:]
        if platform.supportsAppleIntelligence && assets.isAvailable {
            for set in AppleIntelligenceCatalog.availableModelSets(on: version) {
                if let value = assets.downloadedBytes(for: set.name) { bytes[set.name] = value }
            }
        }
        var states: [String: AppleIntelligenceFeatureState] = [:]
        for feature in features {
            states[feature.id] = state(of: feature, bytes: bytes)
        }
        return AppleIntelligenceStatus(
            platform: platform,
            assetsAvailable: assets.isAvailable,
            profile: AppleIntelligenceProfile.installed(using: preferences),
            features: states,
            modelBytes: bytes)
    }

    private func state(
        of feature: AppleIntelligenceFeature, bytes: [String: Int64]
    ) -> AppleIntelligenceFeatureState {
        let forcedOff = feature.restrictions.allSatisfy {
            preferences.isForced(domain: "com.apple.applicationaccess", key: $0)
                && preferences.read(domain: "com.apple.applicationaccess", key: $0)?
                    .matches(.bool(false)) == true
        } && feature.preferences.allSatisfy {
            preferences.isForced(domain: $0.domain, key: $0.key)
                && preferences.read(domain: $0.domain, key: $0.key)?.matches($0.off) == true
        }
        if forcedOff && (!feature.restrictions.isEmpty || !feature.preferences.isEmpty) {
            return .lockedOff
        }
        if !feature.preferences.isEmpty,
           feature.preferences.allSatisfy({
               preferences.read(domain: $0.domain, key: $0.key)?.matches($0.off) == true
           }) {
            return .off
        }
        if feature.restrictions.isEmpty && feature.preferences.isEmpty {
            return modelState(feature.modelSets, bytes: bytes)
        }
        return .on
    }

    private func modelState(
        _ sets: [String], bytes: [String: Int64]
    ) -> AppleIntelligenceFeatureState {
        let readings = sets.map { bytes[$0] }
        if readings.contains(where: { ($0 ?? 0) > 0 }) { return .on }
        return readings.allSatisfy { $0 == 0 } ? .off : .unknown
    }

    // MARK: plan

    /// What turning this selection on would change. Pure: reads the current
    /// status it is given and touches nothing.
    func plan(_ selection: AppleIntelligenceSelection) -> AppleIntelligencePlan {
        let status = status()
        guard status.supported else { return AppleIntelligencePlan() }
        let version = platform.version
        var plan = AppleIntelligencePlan()

        let kept = selection.keep
        plan.featuresTurnedOff = AppleIntelligenceCatalog.availableFeatures(on: version)
            .filter { !kept.contains($0.id) }
        plan.changes = plan.featuresTurnedOff.map { feature in
            AppleIntelligenceChange(
                id: "feature:\(feature.id)",
                title: String(localized: "Turn off \(feature.title)"),
                detail: restrictionSummary(feature),
                isProfile: true)
        }

        plan.tweaks = AppleTweaks.all.filter {
            selection.tweaks.contains($0.id) && $0.isAvailable(on: version)
        }
        for tweak in plan.tweaks {
            for change in tweak.changes {
                plan.changes.append(AppleIntelligenceChange(
                    id: "tweak:\(change.key)",
                    title: tweak.title,
                    detail: change.command,
                    isProfile: change.inProfile))
            }
        }

        let setNames = AppleIntelligenceCatalog.setsToRemove(keeping: kept, on: version)
        plan.modelSets = setNames.compactMap(AppleIntelligenceCatalog.modelSet)
        for set in plan.modelSets {
            if let bytes = status.modelBytes[set.name] { plan.modelBytes[set.name] = bytes }
        }

        let profileTweaks = Set(plan.tweaks.filter(\.inProfile).map(\.id))
        let target = AppleIntelligenceProfileContents(keep: kept, tweaks: profileTweaks)
        let current = status.profile.contents(on: version)
            ?? AppleIntelligenceProfileContents(keep: nil, tweaks: [])
        if target != current {
            plan.profile = target
            plan.changes.append(AppleIntelligenceChange(
                id: "profile",
                title: String(localized: "Review and approve a configuration profile"),
                detail: String(
                    localized: "macOS requires you to approve it in System Settings. Turning these settings off and blocking model downloads is what the profile does."),
                isProfile: true))
        }
        for set in plan.modelSets {
            let size = plan.modelBytes[set.name].map {
                SiftFormat.bytes($0)
            } ?? String(localized: "size unknown")
            plan.changes.append(AppleIntelligenceChange(
                id: "model:\(set.name)",
                title: String(localized: "Delete \(set.title)"),
                detail: size,
                isProfile: false))
        }
        return plan
    }

    private func restrictionSummary(_ feature: AppleIntelligenceFeature) -> String {
        var parts: [String] = []
        parts += feature.restrictions.map { "profile: com.apple.applicationaccess \($0) = false" }
        parts += feature.preferences.map {
            "profile: \($0.domain) \($0.key) = \($0.off) (locked)"
        }
        if parts.isEmpty && !feature.modelSets.isEmpty {
            return String(localized: "Its models are removed and blocked from downloading again.")
        }
        return parts.joined(separator: "\n")
    }

    // MARK: apply

    func apply(_ plan: AppleIntelligencePlan) -> AppleIntelligenceApplyResult {
        var result = AppleIntelligenceApplyResult()
        let version = platform.version
        guard platform.supportsAppleIntelligence, assets.isAvailable else {
            result.problems.append(
                String(localized: "Apple Intelligence management is not available on this Mac."))
            return result
        }

        var entries: [String: AppleTweakJournal.Entry]
        do {
            entries = try journal.load()
        } catch {
            result.problems.append(error.localizedDescription)
            return result
        }

        // Local preferences first: each previous value is journaled before the
        // write, and only once, so a reapply doesn't overwrite the original.
        for tweak in plan.tweaks {
            for change in tweak.changes {
                guard case .preference(let domain, let key, let value) = change else { continue }
                let journalKey = change.key
                if entries[journalKey] == nil {
                    entries[journalKey] = AppleTweakJournal.Entry(
                        tweak: tweak.id, date: Date(),
                        previous: preferences.userValue(domain: domain, key: key))
                }
                preferences.write(value, domain: domain, key: key)
                if preferences.read(domain: domain, key: key)?.matches(value) != true {
                    result.problems.append(
                        String(localized: "\(domain) \(key) did not change."))
                }
            }
        }

        // The profile is written and opened, never installed. Downloads are
        // blocked once the person approves it.
        if let contents = plan.profile {
            do {
                let data = try AppleIntelligenceProfile.data(contents, on: version)
                let url = try profiles.write(data)
                profiles.open(url)
                result.profileURL = url
            } catch {
                result.problems.append(error.localizedDescription)
            }
        }

        // Models last, one set per request, so a set macOS refuses does not
        // stop the rest.
        if !plan.modelSets.isEmpty {
            do {
                try AppleAssetReset.validate(plan.modelSets.map(\.name))
                for set in plan.modelSets {
                    // A set this macOS describes differently is left alone: the
                    // download block would name a type it does not use.
                    guard assets.assetType(for: set.name) == set.assetType else {
                        result.modelProblems.append(
                            String(localized: "\(set.title): this macOS describes it differently, so it was left alone."))
                        continue
                    }
                    switch remove(set: set.name) {
                    case .done:
                        result.modelsRemoved.append(set.name)
                    case let outcome:
                        result.modelProblems.append("\(set.title): \(outcome.explanation)")
                    }
                }
            } catch {
                result.problems.append(error.localizedDescription)
            }
        }

        do {
            try journal.save(entries)
        } catch {
            result.problems.append(error.localizedDescription)
        }
        return result
    }

    private func remove(set: String) -> AppleAssetResetOutcome {
        var outcome = assets.reset(sets: [set])
        for delay in retryDelays where outcome == .locked {
            sleep(delay)
            outcome = assets.reset(sets: [set])
        }
        return outcome
    }

    // MARK: undo

    func undo(_ scope: AppleIntelligenceUndoScope) -> AppleIntelligenceUndoResult {
        var result = AppleIntelligenceUndoResult(needsProfileRemoval: true)
        var entries: [String: AppleTweakJournal.Entry]
        do {
            entries = try journal.load()
        } catch {
            result.problems.append(error.localizedDescription)
            return result
        }

        guard scope == .everything else { return result }

        for key in entries.keys.sorted() {
            guard let entry = entries[key] else { continue }
            guard let key = preferenceKey(from: key) else {
                // A key this version no longer understands stays journaled so
                // a later version can still restore it.
                continue
            }
            preferences.write(entry.previous, domain: key.domain, key: key.key)
            if preferences.read(domain: key.domain, key: key.key)
                .map({ $0.matches(entry.previous) }) ?? (entry.previous == nil) {
                result.restored.append(entry.tweak)
                entries[key.journalKey] = nil
            } else {
                result.problems.append(
                    String(localized: "\(key.domain) \(key.key) could not be restored."))
            }
        }

        do {
            try journal.save(entries)
        } catch {
            result.problems.append(error.localizedDescription)
        }
        return result
    }

    private struct PreferenceKey {
        let domain: String
        let key: String
        let journalKey: String
    }

    private func preferenceKey(from journalKey: String) -> PreferenceKey? {
        let parts = journalKey.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "preference" else { return nil }
        return PreferenceKey(domain: parts[1], key: parts[2], journalKey: journalKey)
    }
}
