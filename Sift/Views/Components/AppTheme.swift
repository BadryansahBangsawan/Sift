import AppKit
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @AppStorage("PureMac.Appearance") private var rawValue = AppearanceMode.system.rawValue

    private init() {
        applyToApp()
    }

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: rawValue) ?? .system }
        set {
            rawValue = newValue.rawValue
            objectWillChange.send()
            applyToApp()
        }
    }

    func applyToApp() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }
}
