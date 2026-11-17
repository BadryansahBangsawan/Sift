import AppKit
import SwiftUI

// Sift design tokens. Dark values come straight from the Pairdraw design
// ("Sift v2 — Rounded"); light values are derived to keep the same hierarchy.

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Linear sRGB mix: 0 returns `self`, 1 returns `other`.
    func mixed(with other: NSColor, _ amount: CGFloat) -> NSColor {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        let t = max(0, min(1, amount))
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            alpha: 1
        )
    }
}

private func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

private func dynamic(dark: UInt32, light: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { isDark($0) ? NSColor(hex: dark) : NSColor(hex: light) })
}

private func dynamic(_ resolve: @escaping (_ dark: Bool) -> NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { resolve(isDark($0)) })
}

// MARK: - Accent

/// The accent swatches offered in Settings. Brass is the shipped accent.
enum SiftAccent: String, CaseIterable, Identifiable {
    case brass, green, blue, orange, graphite

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .brass: return "Brass"
        case .green: return "Green"
        case .blue: return "Blue"
        case .orange: return "Orange"
        case .graphite: return "Graphite"
        }
    }

    /// Base color on dark surfaces (the design's swatch).
    var darkBase: NSColor {
        switch self {
        case .brass: return NSColor(hex: 0xC9A227)
        case .green: return NSColor(hex: 0x4FD08B)
        case .blue: return NSColor(hex: 0x6FA8F0)
        case .orange: return NSColor(hex: 0xF08A4B)
        case .graphite: return NSColor(hex: 0x9AA1A6)
        }
    }

    /// Base color on light surfaces, darkened for contrast against white.
    var lightBase: NSColor {
        switch self {
        case .brass: return NSColor(hex: 0xA8851A)
        case .green: return NSColor(hex: 0x23955A)
        case .blue: return NSColor(hex: 0x2F6FC4)
        case .orange: return NSColor(hex: 0xC8611F)
        case .graphite: return NSColor(hex: 0x5D646A)
        }
    }
}

/// Persists the chosen accent. The app root re-renders on change.
@MainActor
final class AccentStore: ObservableObject {
    static let shared = AccentStore()
    static let defaultsKey = "PureMac.Accent"

    @Published var accent: SiftAccent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        accent = SiftAccent(rawValue: UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "") ?? .brass
    }

    /// Read from color providers, which may run off the main actor.
    nonisolated static var current: SiftAccent {
        SiftAccent(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .brass
    }
}

// MARK: - Colors

enum SiftColor {
    // Surfaces
    static let window = dynamic(dark: 0x0D0F11, light: 0xF1EFE9)
    static let rail = dynamic(dark: 0x101316, light: 0xF8F7F3)
    static let card = dynamic(dark: 0x14171A, light: 0xFFFFFF)
    /// Raised controls and inset panels inside a card.
    static let control = dynamic(dark: 0x1A1E22, light: 0xF4F2ED)
    static let selected = dynamic(dark: 0x1F2428, light: 0xEAE7E0)
    static let badge = dynamic(dark: 0x171B1E, light: 0xF1EFEA)
    static let track = dynamic(dark: 0x1E2327, light: 0xE7E4DD)
    static let meterUsed = dynamic(dark: 0x23282D, light: 0xE3E0D8)
    static let meterFree = dynamic(dark: 0x171A1D, light: 0xFAF9F6)

    // Strokes
    static let stroke = dynamic(dark: 0x1E2327, light: 0xE4E1D8)
    static let controlStroke = dynamic(dark: 0x262B30, light: 0xDAD6CC)
    static let checkboxFill = dynamic(dark: 0x15181B, light: 0xFFFFFF)
    static let checkboxStroke = dynamic(dark: 0x353B41, light: 0xC4C0B6)
    static let switchOff = dynamic(dark: 0x262B30, light: 0xDAD6CC)
    static let switchOffHover = dynamic(dark: 0x2F353B, light: 0xCFCBC1)

    // Text and icons
    static let textPrimary = dynamic(dark: 0xF1EFEA, light: 0x17191B)
    static let textSecondary = dynamic(dark: 0x9AA1A6, light: 0x50575D)
    static let icon = dynamic(dark: 0x7F878D, light: 0x6A7177)
    static let textTertiary = dynamic(dark: 0x6B7278, light: 0x7D848A)
    static let faint = dynamic(dark: 0x3A4046, light: 0xC2C6C9)

    // Status
    static let success = dynamic(dark: 0x4FD08B, light: 0x1F8A50)
    static let successBackground = dynamic(dark: 0x16241D, light: 0xE3F4EA)
    static let warning = dynamic(dark: 0xF08A4B, light: 0xB9551A)
    static let warningBackground = dynamic(dark: 0x2A1A12, light: 0xFCEBDF)
    static let warningStroke = dynamic(dark: 0x5A3420, light: 0xF1C7AB)
    static let info = dynamic(dark: 0x4CA3E6, light: 0x2468B3)
    static let infoBackground = dynamic(dark: 0x1A2633, light: 0xE2EEF9)

    // Accent (follows the Settings accent picker)
    private static func accentColor(_ build: @escaping (_ base: NSColor, _ dark: Bool) -> NSColor) -> Color {
        dynamic { dark in
            let accent = AccentStore.current
            return build(dark ? accent.darkBase : accent.lightBase, dark)
        }
    }

    static let accent = accentColor { base, _ in base }
    static let accentHover = accentColor { base, dark in
        AccentStore.current == .brass && dark ? NSColor(hex: 0xD9B23A) : base.mixed(with: .white, dark ? 0.12 : 0.1)
    }
    /// Shortcut-key chip sitting on an accent button.
    static let accentPressed = accentColor { base, dark in
        AccentStore.current == .brass && dark ? NSColor(hex: 0xB08C1E) : base.mixed(with: .black, 0.13)
    }
    /// Text and icons placed on an accent fill.
    static let onAccent = accentColor { _, dark in dark ? NSColor(hex: 0x0D0F11) : .white }
    /// Secondary text placed on an accent fill.
    static let onAccentMuted = accentColor { base, dark in
        AccentStore.current == .brass && dark ? NSColor(hex: 0x3A3115) : base.mixed(with: dark ? NSColor(hex: 0x0D0F11) : .white, 0.72)
    }
    /// Soft accent background (icon tiles, selected rows).
    static let accentTint = accentColor { base, dark in
        AccentStore.current == .brass && dark ? NSColor(hex: 0x2A2412) : base.mixed(with: dark ? NSColor(hex: 0x14171A) : .white, dark ? 0.88 : 0.86)
    }
    /// Very soft accent wash for selected list rows.
    static let accentWash = accentColor { base, dark in
        base.mixed(with: dark ? NSColor(hex: 0x14171A) : .white, dark ? 0.93 : 0.93)
    }
    /// Muted accent for secondary bars.
    static let accentDim = accentColor { base, dark in
        AccentStore.current == .brass && dark ? NSColor(hex: 0x5A5130) : base.mixed(with: dark ? NSColor(hex: 0x14171A) : .white, dark ? 0.6 : 0.55)
    }
}

// MARK: - Metrics

enum SiftRadius {
    static let hero: CGFloat = 28
    static let card: CGFloat = 24
    static let panel: CGFloat = 20
    static let row: CGFloat = 14
    static let nav: CGFloat = 12
    static let tile: CGFloat = 10
    static let checkbox: CGFloat = 7
}

enum SiftSpacing {
    /// Outer window padding and the gap between top-level cards.
    static let gutter: CGFloat = 12
    static let cardPadding: CGFloat = 20
    static let heroPadding: CGFloat = 24
    static let railWidth: CGFloat = 228
}

enum SiftMotion {
    static let quick = Animation.easeOut(duration: 0.14)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.84)
}
