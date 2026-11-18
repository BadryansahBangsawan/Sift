import Foundation

struct AppleFeature: Identifiable {
    let id: String
    let title: String
    let summary: String
    let steps: String
    let destination: String
    let guide: URL
    let minimumVersion: OperatingSystemVersion

    func isAvailable(on version: OperatingSystemVersion) -> Bool {
        let actual = [version.majorVersion, version.minorVersion, version.patchVersion]
        let required = [minimumVersion.majorVersion, minimumVersion.minorVersion, minimumVersion.patchVersion]
        return !actual.lexicographicallyPrecedes(required)
    }
}

enum AppleFeatureCatalog {
    static func features(for version: OperatingSystemVersion) -> [AppleFeature] {
        let modern = version.majorVersion >= 27
        let legacyGuideVersion = version.majorVersion < 26 ? "15.0/mac/15.0" : "26/mac/26"
        let siriPane = "com.apple.Siri-Settings.extension"
        let screenTime = "com.apple.Screen-Time-Settings.extension"
        let restrictionsGuide = modern ? "z25xrnykpuln/mac" : "mchlb2e44f94/\(legacyGuideVersion)"
        let restrictions = modern
            ? String(localized: "Open Screen Time > Content & Privacy Restrictions. Enable All Restrictions, then open Siri. These restrictions may apply across devices using your Apple Account.")
            : String(localized: "Open Screen Time > Content & Privacy. Enable Content & Privacy restrictions, then open Intelligence & Siri.")
        func feature(_ id: String, _ title: String, _ summary: String, _ steps: String, _ destination: String, _ guide: String, _ major: Int = 13, _ minor: Int = 0) -> AppleFeature {
            AppleFeature(id: id, title: title, summary: summary,
                         steps: steps, destination: destination,
                         guide: URL(string: "https://support.apple.com/guide/mac-help/\(guide)")!,
                         minimumVersion: OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0))
        }
        var items = [
            feature("siri", String(localized: "Siri"), String(localized: "Turn off the assistant and its activation controls."),
                    modern ? String(localized: "Open Siri and choose Turn Off Siri. Confirm the change. Screen Time also offers Don't Allow Siri.")
                        : String(localized: "Open Siri or Apple Intelligence & Siri and turn off Ask Siri. On versions that show a Siri section, open it to find the control."),
                    siriPane, modern ? "mchl3fd7fc15/mac" : "mchl3fd7fc15/26/mac/26"),
            feature("intelligence", String(localized: "Apple Intelligence"), String(localized: "Review Apple's writing, image and summary features."),
                    modern ? String(localized: "macOS 27 uses separate Siri, Screen Time and app controls. Review the individual features below. Turning off Siri does not establish that all Apple Intelligence features are off.")
                        : String(localized: "Open Apple Intelligence & Siri, turn off Apple Intelligence and confirm. macOS manages downloaded models; Sift does not promise that this immediately recovers their storage."),
                    siriPane, modern ? "mchlb2e44f94/mac" : "mchl46361784/\(legacyGuideVersion)", 15, 1),
            feature("images", String(localized: "Image Playground & Genmoji"), String(localized: "Restrict image generation using Screen Time."),
                    restrictions + (modern ? String(localized: " Set Image Creation to Blocked where available.") : String(localized: " Turn off Image Creation.")) + String(localized: " This restricts access; it does not uninstall the protected app or erase images you created."),
                    screenTime, restrictionsGuide, 15, 2),
            feature("writing", modern ? String(localized: "Writing Assistance") : String(localized: "Writing Tools"), String(localized: "Restrict Apple's generated writing features."),
                    restrictions + (modern ? String(localized: " Set Writing Assistance to Blocked where available.") : String(localized: " Turn off Writing Tools.")),
                    screenTime, restrictionsGuide, 15, 1),
            feature("summaries", String(localized: "Notification summaries"), String(localized: "Read original notification text without generated summaries."),
                    String(localized: "Open Notifications > Summarize Notifications and turn it off, or choose which apps can use summaries."),
                    "com.apple.Notifications-Settings.extension", "mchlb2e44f94/mac", 15, 1),
            feature("mail", String(localized: "Mail summaries"), String(localized: "Turn off generated previews in Apple Mail."),
                    String(localized: "In Mail, choose Mail > Settings > Viewing, then turn off Summarize Message Previews. The button opens Mail; finish the change in its settings."),
                    "application:com.apple.mail", "mchlb2e44f94/mac", 15, 1),
            feature("predictions", String(localized: "Inline text predictions"), String(localized: "Stop suggested completions appearing as you type."),
                    String(localized: "Open Keyboard > Text Input > Edit and turn off Show inline predictive text. This setting is separate from Apple Intelligence."),
                    "com.apple.Keyboard-Settings.extension", "mchlp2299/mac", 14),
            feature("analytics", String(localized: "Analytics & Siri recordings"), String(localized: "Review diagnostic and voice-recording sharing with Apple."),
                    String(localized: "Open Privacy & Security > Analytics & Improvements. Review Share Mac Analytics, Improve Siri & Dictation and Share iCloud Analytics. Available switches depend on your Mac and account."),
                    "com.apple.preference.security?Privacy_Analytics", "mchl211c911f/27/mac/27"),
            feature("advertising", String(localized: "Personalized Apple ads"), String(localized: "Turn off interest-based ad targeting by Apple."),
                    String(localized: "Open Privacy & Security > Apple Advertising and turn off Personalized Ads. This changes ad targeting; it does not remove advertising or reduce the number of ads."),
                    "com.apple.preference.security?Privacy_Advertising", "mchl211c911f/27/mac/27")
        ]
        items.insert(feature("extensions", String(localized: "ChatGPT & intelligence extensions"), String(localized: "Control access to external AI providers."),
                             restrictions + (modern ? String(localized: " Set Extensions to Blocked. This does not uninstall standalone provider apps.")
                                 : String(localized: " Turn off Intelligence Extensions. You can also open Apple Intelligence & Siri > ChatGPT to review its controls.")),
                             screenTime, restrictionsGuide, 15, 2), at: 4)
        return items
    }
}
