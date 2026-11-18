import AppKit
import CryptoKit
import Foundation

/// What the configuration profile holds. `keep` is nil when Apple Intelligence
/// is left alone; model blocks and restrictions are derived from it.
struct AppleIntelligenceProfileContents: Equatable {
    var keep: Set<String>?
    var tweaks: Set<String> = []

    var isEmpty: Bool { keep == nil && tweaks.isEmpty }
}

/// The configuration profile that macOS requires a person to approve. Sift
/// writes the file and opens it; it never installs the profile itself.
enum AppleIntelligenceProfile {
    static let identifier = "com.sift.appleintelligence"
    static let downloadDomain = "com.apple.MobileAsset"
    static let downloadKeyPrefix = "DownloadServerBaseURLOverride-"
    static let blockedURL = "https://127.0.0.1:9/sift-blocked/"
    static let displayName = "Sift Apple Intelligence"

    static func downloadKey(_ set: AppleIntelligenceModelSet) -> String {
        downloadKeyPrefix + set.assetType
    }

    /// The profile for a macOS version: Apple Intelligence off except the kept
    /// features, the blocked download URL for every removed set, and the chosen
    /// tweaks.
    static func data(
        _ contents: AppleIntelligenceProfileContents,
        on version: OperatingSystemVersion
    ) throws -> Data {
        let features = AppleIntelligenceCatalog.availableFeatures(on: version)
        var restrictions = payload(
            type: "com.apple.applicationaccess", suffix: "restrictions", name: "Restrictions")
        var forced: [String: [String: Any]] = [:]

        if let kept = contents.keep {
            for feature in features where !kept.contains(feature.id) {
                for key in feature.restrictions { restrictions[key] = false }
                for preference in feature.preferences {
                    forced[preference.domain, default: [:]][preference.key] = preference.off.object
                }
            }
            for name in AppleIntelligenceCatalog.setsToRemove(keeping: kept, on: version) {
                guard let set = AppleIntelligenceCatalog.modelSet(name) else { continue }
                forced[downloadDomain, default: [:]][downloadKey(set)] = blockedURL
            }
        }
        for tweak in AppleTweaks.all
        where contents.tweaks.contains(tweak.id) && tweak.isAvailable(on: version) {
            for change in tweak.changes {
                switch change {
                case .restriction(let key):
                    restrictions[key] = false
                case .forced(let domain, let key, let value):
                    forced[domain, default: [:]][key] = value.object
                case .preference:
                    break
                }
            }
        }

        // A marker of Sift's own, so status can tell the profile is in force
        // and what it was made with.
        var marker: [String: Any] = [
            "installed": true,
            "ai": contents.keep != nil,
            "tweaks": contents.tweaks.sorted().joined(separator: ","),
        ]
        marker["kept"] = (contents.keep ?? []).sorted().joined(separator: ",")
        marker["features"] = features.map(\.id).sorted().joined(separator: ",")
        forced[identifier] = marker

        let preferences = forced.keys.sorted().map { domain -> [String: Any] in
            var payload = payload(
                type: "com.apple.ManagedClient.preferences",
                suffix: "preferences." + domain,
                name: "Forced settings: \(domain)")
            payload["PayloadContent"] = [
                domain: ["Forced": [["mcx_preference_settings": forced[domain]!]]]
            ]
            return payload
        }

        var profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier,
            "PayloadUUID": uuid(identifier),
            "PayloadDisplayName": displayName,
            "PayloadDescription": String(
                localized: "Turns off Apple Intelligence and the settings chosen in Sift, and stops removed models downloading again. Remove this profile to undo."),
            "PayloadOrganization": "Sift",
            "PayloadScope": "System",
            "PayloadRemovalDisallowed": false,
        ]
        let hasRestrictions = restrictions.keys.contains { $0.hasPrefix("allow") }
        profile["PayloadContent"] = (hasRestrictions ? [restrictions] : []) + preferences
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    private static func payload(type: String, suffix: String, name: String) -> [String: Any] {
        let id = identifier + "." + suffix
        return [
            "PayloadType": type,
            "PayloadVersion": 1,
            "PayloadIdentifier": id,
            "PayloadUUID": uuid(id),
            "PayloadDisplayName": name,
        ]
    }

    /// A stable UUID per payload (version 5 style, from its identifier), so
    /// approving a new version replaces the old one.
    static func uuid(_ name: String) -> String {
        var bytes = Array(Insecure.SHA1.hash(data: Data(name.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                   bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        ).uuidString
    }

    struct Installed: Equatable {
        var on = false
        var ai = false
        var kept: Set<String> = []
        var tweaks: Set<String> = []
        /// The features the profile was made for. Older profiles don't record them.
        var features: Set<String>? = nil

        /// Made on an older macOS that lacked some of this one's features, so
        /// it leaves them on and has to be approved again.
        func isStale(on version: OperatingSystemVersion) -> Bool {
            guard ai, let features else { return false }
            return !Set(AppleIntelligenceCatalog.availableFeatures(on: version).map(\.id))
                .isSubset(of: features)
        }

        func contents(on version: OperatingSystemVersion) -> AppleIntelligenceProfileContents? {
            guard on else { return nil }
            return AppleIntelligenceProfileContents(
                keep: ai && !isStale(on: version) ? kept : nil, tweaks: tweaks)
        }
    }

    /// Whether Sift's profile is in force, and what it holds.
    static func installed(using preferences: ApplePreferenceStoring) -> Installed {
        guard preferences.isForced(domain: identifier, key: "installed") else { return Installed() }
        func list(_ key: String) -> Set<String> {
            let value = preferences.read(domain: identifier, key: key)?.description ?? ""
            return Set(value.split(separator: ",").map(String.init))
        }
        let ai = preferences.read(domain: identifier, key: "ai")?.matches(.bool(true)) ?? true
        let features = preferences.read(domain: identifier, key: "features") == nil
            ? nil : list("features")
        return Installed(
            on: true, ai: ai, kept: list("kept"), tweaks: list("tweaks"), features: features)
    }
}

/// Writes the profile file and opens it for approval. Sift never installs it.
protocol AppleProfileWriting {
    func write(_ data: Data) throws -> URL
    func open(_ url: URL)
}

struct FinderProfileWriter: AppleProfileWriting {
    static let fileName = "Sift-AppleIntelligence.mobileconfig"

    var directory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)

    func write(_ data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
