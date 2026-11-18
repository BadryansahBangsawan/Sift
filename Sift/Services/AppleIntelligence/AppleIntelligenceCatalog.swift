import Foundation

/// A preference a feature needs off, written into the configuration profile
/// while the feature is being turned off.
struct AppleIntelligenceForcedPreference: Equatable {
    let domain: String
    let key: String
    let off: ApplePreferenceValue
}

/// One Apple Intelligence feature a person can keep. Keys and model sets follow
/// RemoveMacAI's catalog, which pared (MIT) first mapped.
struct AppleIntelligenceFeature: Identifiable, Equatable {
    let id: String
    let title: String
    let restrictions: [String]
    let preferences: [AppleIntelligenceForcedPreference]
    let modelSets: [String]
    /// The first macOS version that has the feature.
    let since: (major: Int, minor: Int)

    func isAvailable(on version: OperatingSystemVersion) -> Bool {
        (version.majorVersion, version.minorVersion) >= since
    }

    static func == (lhs: AppleIntelligenceFeature, rhs: AppleIntelligenceFeature) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.restrictions == rhs.restrictions && lhs.preferences == rhs.preferences
            && lhs.modelSets == rhs.modelSets
            && lhs.since == rhs.since
    }
}

/// A downloadable model set in Apple's asset service.
struct AppleIntelligenceModelSet: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let assetType: String
    let title: String
}

enum AppleIntelligenceCatalog {
    static let foundationModels = "com.apple.modelcatalog"
    static let visualModels = "com.apple.MobileAsset.UAF.FM.Visual"
    static let codeModels = "com.apple.MobileAsset.UAF.FM.CodeLM"
    static let cleanUpModels = "com.apple.MobileAsset.UAF.Photos.MagicCleanup"
    static let spatialModels = "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive"

    static let modelSets: [AppleIntelligenceModelSet] = [
        AppleIntelligenceModelSet(
            name: foundationModels,
            assetType: "com.apple.MobileAsset.UAF.FM.GenerativeModels",
            title: String(localized: "Apple Intelligence foundation models")),
        AppleIntelligenceModelSet(
            name: visualModels, assetType: visualModels,
            title: String(localized: "Image and Genmoji models")),
        AppleIntelligenceModelSet(
            name: spatialModels, assetType: spatialModels,
            title: String(localized: "Spatial Photos models")),
        AppleIntelligenceModelSet(
            name: cleanUpModels, assetType: cleanUpModels,
            title: String(localized: "Photos Clean Up models")),
        AppleIntelligenceModelSet(
            name: codeModels, assetType: codeModels,
            title: String(localized: "Xcode code completion models")),
    ]

    static let features: [AppleIntelligenceFeature] = [
        AppleIntelligenceFeature(
            id: "siri",
            title: String(localized: "Siri and Siri AI"),
            restrictions: ["allowAssistant"],
            preferences: [
                AppleIntelligenceForcedPreference(
                    domain: "com.apple.assistant.support", key: "Assistant Enabled", off: .bool(false)),
                AppleIntelligenceForcedPreference(
                    domain: "com.apple.Siri", key: "StatusMenuVisible", off: .bool(false)),
                AppleIntelligenceForcedPreference(
                    domain: "com.apple.Siri", key: "VoiceTriggerUserEnabled", off: .bool(false)),
            ],
            modelSets: [foundationModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "chatgpt",
            title: String(localized: "ChatGPT and other AI extensions"),
            restrictions: [
                "allowExternalIntelligenceIntegrations",
                "allowExternalIntelligenceIntegrationsSignIn",
            ],
            preferences: [], modelSets: [], since: (15, 2)),
        AppleIntelligenceFeature(
            id: "writing-tools",
            title: String(localized: "Writing Tools"),
            restrictions: ["allowWritingTools"], preferences: [],
            modelSets: [foundationModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "genmoji",
            title: String(localized: "Genmoji"),
            restrictions: ["allowGenmoji"], preferences: [],
            modelSets: [foundationModels, visualModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "image-playground",
            title: String(localized: "Image Playground"),
            restrictions: ["allowImagePlayground"], preferences: [],
            modelSets: [foundationModels, visualModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "mail",
            title: String(localized: "Mail summaries and smart replies"),
            restrictions: ["allowMailSummary", "allowMailSmartReplies"],
            preferences: [
                AppleIntelligenceForcedPreference(
                    domain: "group.com.apple.mail", key: "DisableAutomaticMessageSummarization",
                    off: .bool(true)),
                AppleIntelligenceForcedPreference(
                    domain: "group.com.apple.mail", key: "PersonalizedSmartReplies", off: .bool(false)),
            ],
            modelSets: [foundationModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "notification-summaries",
            title: String(localized: "Notification summaries"),
            restrictions: [],
            preferences: [
                AppleIntelligenceForcedPreference(
                    domain: "group.com.apple.usernoted", key: "summarize_previews", off: .bool(false))
            ],
            modelSets: [foundationModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "messages-summaries",
            title: String(localized: "Messages summaries"),
            restrictions: [],
            preferences: [
                AppleIntelligenceForcedPreference(
                    domain: "com.apple.MobileSMS", key: "messageSummarizationEnabled",
                    off: .bool(false))
            ],
            modelSets: [foundationModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "safari-summaries",
            title: String(localized: "Safari summaries"),
            restrictions: ["allowSafariSummary"], preferences: [],
            modelSets: [foundationModels], since: (15, 4)),
        AppleIntelligenceFeature(
            id: "notes-summaries",
            title: String(localized: "Notes transcription summaries"),
            restrictions: ["allowNotesTranscriptionSummary"], preferences: [],
            modelSets: [foundationModels], since: (15, 3)),
        AppleIntelligenceFeature(
            id: "inline-predictions",
            title: String(localized: "Inline text predictions"),
            restrictions: [],
            preferences: [
                AppleIntelligenceForcedPreference(
                    domain: ".GlobalPreferences", key: "NSAutomaticInlinePredictionEnabled",
                    off: .bool(false))
            ],
            modelSets: [], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "spatial-photos",
            title: String(localized: "Spatial Photos"),
            restrictions: [],
            preferences: [
                AppleIntelligenceForcedPreference(
                    domain: "com.apple.spatialphotosrelive", key: "LocallyDisabled", off: .bool(true))
            ],
            modelSets: [spatialModels], since: (26, 0)),
        AppleIntelligenceFeature(
            id: "photos-clean-up",
            title: String(localized: "Photos Clean Up"),
            restrictions: [], preferences: [],
            modelSets: [cleanUpModels], since: (15, 1)),
        AppleIntelligenceFeature(
            id: "xcode-completion",
            title: String(localized: "Xcode predictive code completion"),
            restrictions: [], preferences: [],
            modelSets: [codeModels], since: (15, 1)),
    ]

    static func feature(_ id: String) -> AppleIntelligenceFeature? {
        features.first { $0.id == id }
    }

    static func modelSet(_ name: String) -> AppleIntelligenceModelSet? {
        modelSets.first { $0.name == name }
    }

    /// The features the running macOS has.
    static func availableFeatures(on version: OperatingSystemVersion) -> [AppleIntelligenceFeature] {
        features.filter { $0.isAvailable(on: version) }
    }

    /// The model sets the running macOS has: those an available feature names.
    static func availableModelSets(on version: OperatingSystemVersion) -> [AppleIntelligenceModelSet] {
        let available = availableFeatures(on: version)
        return modelSets.filter { set in available.contains { $0.modelSets.contains(set.name) } }
    }

    /// The sets to remove: every available set whose features are all being
    /// turned off. A set a kept feature still needs stays.
    static func setsToRemove(keeping kept: Set<String>, on version: OperatingSystemVersion) -> [String] {
        let available = availableFeatures(on: version)
        return availableModelSets(on: version).map(\.name).filter { set in
            let users = available.filter { $0.modelSets.contains(set) }
            return !users.isEmpty && users.allSatisfy { !kept.contains($0.id) }
        }
    }
}

// MARK: - Optional tweaks

enum AppleTweakGroup: String, CaseIterable, Identifiable {
    case privacy, annoyances

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return String(localized: "Privacy")
        case .annoyances: return String(localized: "Annoyances")
        }
    }
}

enum AppleTweakChange: Equatable {
    /// A restriction key the profile sets to false.
    case restriction(String)
    /// A preference the profile forces.
    case forced(String, String, ApplePreferenceValue)
    /// A preference written for the current user, journaled first.
    case preference(String, String, ApplePreferenceValue)

    var inProfile: Bool {
        switch self {
        case .restriction, .forced: return true
        case .preference: return false
        }
    }

    var key: String {
        switch self {
        case .restriction(let key): return "restriction:\(key)"
        case .forced(let domain, let key, _): return "forced:\(domain):\(key)"
        case .preference(let domain, let key, _): return "preference:\(domain):\(key)"
        }
    }

    var command: String {
        switch self {
        case .restriction(let key): return "profile: com.apple.applicationaccess \(key) = false"
        case .forced(let domain, let key, let value):
            return "profile: \(domain) \(key) = \(value) (locked)"
        case .preference(let domain, let key, let value):
            return "defaults write \(domain) \"\(key)\" \(value.commandType) \(value)"
        }
    }
}

struct AppleTweak: Identifiable, Equatable {
    let id: String
    let group: AppleTweakGroup
    let title: String
    let detail: String
    var caveat: String? = nil
    let changes: [AppleTweakChange]
    var presets: Set<AppleTweakPreset> = []
    var since: (major: Int, minor: Int) = (14, 0)

    func isAvailable(on version: OperatingSystemVersion) -> Bool {
        (version.majorVersion, version.minorVersion) >= since
    }

    static func == (lhs: AppleTweak, rhs: AppleTweak) -> Bool {
        lhs.id == rhs.id && lhs.group == rhs.group && lhs.title == rhs.title
            && lhs.detail == rhs.detail && lhs.caveat == rhs.caveat
            && lhs.changes == rhs.changes && lhs.presets == rhs.presets
            && lhs.since == rhs.since
    }

    var inProfile: Bool { changes.contains { $0.inProfile } }
}

enum AppleTweakPreset: String, CaseIterable, Identifiable {
    case recommended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended: return String(localized: "Recommended")
        }
    }

    var summary: String {
        switch self {
        case .recommended:
            return String(localized: "Apple Intelligence off, no analytics or ads, fewer pop-ups. Nothing you rely on stops working.")
        }
    }
}

enum AppleTweaks {
    static let all: [AppleTweak] = [
        AppleTweak(
            id: "analytics", group: .privacy,
            title: String(localized: "Turn off Mac Analytics"),
            detail: String(localized: "Stops your Mac sending diagnostic and usage data to Apple and to app developers."),
            changes: [.restriction("allowDiagnosticSubmission")],
            presets: [.recommended]),
        AppleTweak(
            id: "personalized-ads", group: .privacy,
            title: String(localized: "Turn off personalized ads"),
            detail: String(localized: "Stops Apple using what you do in its apps to target ads in the App Store, News and Stocks."),
            changes: [.restriction("allowApplePersonalizedAdvertising")],
            presets: [.recommended]),
        AppleTweak(
            id: "improve-siri", group: .privacy,
            title: String(localized: "Turn off Improve Siri and Dictation"),
            detail: String(localized: "Stops Apple storing and reviewing recordings of your Siri and dictation requests."),
            changes: [.forced("com.apple.assistant.support", "Siri Data Sharing Opt-In Status", .int(2))],
            presets: [.recommended]),
        AppleTweak(
            id: "improve-search", group: .privacy,
            title: String(localized: "Turn off Improve Search"),
            detail: String(localized: "Stops Apple keeping your Spotlight, Safari and Look Up searches to improve search."),
            changes: [.forced("com.apple.assistant.support", "Search Queries Data Sharing Status", .int(2))],
            presets: [.recommended]),
        AppleTweak(
            id: "spotlight-web", group: .privacy,
            title: String(localized: "Turn off Spotlight internet results"),
            detail: String(localized: "Keeps Spotlight searches on your Mac instead of sending them to Apple for web suggestions."),
            changes: [.restriction("allowSpotlightInternetResults")],
            presets: [.recommended]),
        AppleTweak(
            id: "lookup-suggestions", group: .privacy,
            title: String(localized: "Turn off Look Up suggestions"),
            detail: String(localized: "Stops Look Up sending the words you select to Apple for web results."),
            changes: [.forced("com.apple.lookup.shared", "LookupSuggestionsDisabled", .bool(true))],
            presets: [.recommended]),
        AppleTweak(
            id: "safari-suggestions", group: .privacy,
            title: String(localized: "Turn off Safari search suggestions"),
            detail: String(localized: "Stops Safari sending what you type in the address bar to your search engine and to Apple."),
            caveat: String(localized: "The address bar no longer suggests searches as you type."),
            changes: [
                .forced("com.apple.Safari", "UniversalSearchEnabled", .bool(false)),
                .forced("com.apple.Safari", "SuppressSearchSuggestions", .bool(true)),
            ]),
        AppleTweak(
            id: "click-to-desktop", group: .annoyances,
            title: String(localized: "Stop clicks on the wallpaper hiding windows"),
            detail: String(localized: "Stops every window sliding away when you click the wallpaper by mistake."),
            changes: [.preference("com.apple.WindowManager", "EnableStandardClickToShowDesktop", .bool(false))],
            presets: [.recommended]),
        AppleTweak(
            id: "desktop-widgets", group: .annoyances,
            title: String(localized: "Hide desktop widgets"),
            detail: String(localized: "Hides widgets on the desktop, including in Stage Manager."),
            changes: [
                .preference("com.apple.WindowManager", "StandardHideWidgets", .bool(true)),
                .preference("com.apple.WindowManager", "StageManagerHideWidgets", .bool(true)),
            ]),
        AppleTweak(
            id: "iphone-mirroring", group: .annoyances,
            title: String(localized: "Turn off iPhone Mirroring"),
            detail: String(localized: "Turns iPhone Mirroring off, so the app and its prompts go away."),
            changes: [.restriction("allowiPhoneMirroring")], since: (15, 0)),
    ]

    static func tweak(_ id: String) -> AppleTweak? { all.first { $0.id == id } }

    /// Tweaks a preset selects on this macOS.
    static func preset(_ preset: AppleTweakPreset, on version: OperatingSystemVersion) -> [AppleTweak] {
        all.filter { $0.presets.contains(preset) && $0.isAvailable(on: version) }
    }
}
