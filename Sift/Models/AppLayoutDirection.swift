import SwiftUI

/// The layout direction of the app's own language, not of the system.
///
/// macOS gives SwiftUI's `\.layoutDirection` the system's interface direction:
/// an app resolved to Arabic by `-AppleLanguages` or by Sift's language picker
/// still lays out its windows, popover and Settings left-to-right (proven on
/// macOS 26 with an Arabic-localized bundle). Each scene root therefore sets
/// the direction from the localization the bundle actually resolved, and every
/// sheet, popover and alert inherits it.
enum AppLayoutDirection {
    /// The app's direction after launch. `Bundle.main.preferredLocalizations`
    /// is what chose the strings on screen: the picker's AppleLanguages, a
    /// launch argument, or the system language, in that order.
    static var current: LayoutDirection {
        direction(for: Bundle.main.preferredLocalizations)
    }

    /// Direction of the first localization the bundle supports.
    static func direction(for preferredLanguages: [String]) -> LayoutDirection {
        for language in preferredLanguages {
            return direction(forLanguage: language)
        }
        return .leftToRight
    }

    /// Direction of one language identifier (`ar`, `ar-SA`, `ar_SA`).
    /// The shipped RTL language is Arabic; the others are here so a system
    /// language the app does not ship cannot claim a direction it does not use.
    static func direction(forLanguage identifier: String) -> LayoutDirection {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let code = normalized.split(separator: "-").first.map(String.init) ?? normalized
        return rightToLeftLanguages.contains(code) ? .rightToLeft : .leftToRight
    }

    static let rightToLeftLanguages: Set<String> = [
        "ar", "arc", "ckb", "dv", "fa", "he", "ks", "ku", "nqo", "ps", "sd", "ug", "ur", "yi",
    ]
}

extension View {
    /// Pins a view tree to `direction`. Scene roots pass
    /// `AppLayoutDirection.current`; the tests pass a direction they choose.
    func siftLayoutDirection(_ direction: LayoutDirection) -> some View {
        environment(\.layoutDirection, direction)
    }

    /// A sheet or popover is its own hosting root on macOS: it does not inherit
    /// the window's `layoutDirection`, so every presentation wraps its content
    /// with this. (`NSAlert`-drawn alerts take the system direction regardless
    /// of the SwiftUI environment and cannot be turned here.)
    func siftPresentedLayout(_ direction: LayoutDirection = AppLayoutDirection.current) -> some View {
        siftLayoutDirection(direction)
    }

    /// Values that read the same in every language — byte counts, paths,
    /// bundle ids, key equivalents — keep their order inside an RTL row.
    func siftLeftToRightValue() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}
