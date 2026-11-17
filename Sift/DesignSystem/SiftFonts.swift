import AppKit
import CoreText
import SwiftUI

/// The three bundled OFL families from the Sift design, registered once per
/// process on first use. Every font factory falls back to the matching system
/// font when a file is missing, so a broken bundle never breaks layout.
enum SiftFonts {
    /// Body and UI text.
    static let ui = "Archivo"
    /// Headlines, page titles and big numbers.
    static let display = "Archivo Narrow"
    /// Sizes, paths, counts and shortcut hints.
    static let mono = "Chivo Mono"

    static let files = ["Archivo", "ArchivoNarrow", "ChivoMono"]

    /// Families that registered successfully. Reading it triggers registration.
    static let registeredFamilies: Set<String> = register(in: .main)

    @discardableResult
    static func register(in bundle: Bundle) -> Set<String> {
        var families = Set<String>()
        for name in files {
            guard let url = bundle.url(forResource: name, withExtension: "ttf")
                ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Already registered by an earlier call is fine; anything else is not.
                let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
                guard code == CTFontManagerError.alreadyRegistered.rawValue else { continue }
            }
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for descriptor in descriptors {
                if let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String {
                    families.insert(family)
                }
            }
        }
        return families
    }

    /// An NSFont of `family` at `weight` (100–900, CSS scale), set through the
    /// font's variable `wght` axis.
    static func nsFont(_ family: String, size: CGFloat, weight: CGFloat) -> NSFont? {
        guard registeredFamilies.contains(family) else { return nil }
        let wghtAxis = NSNumber(value: 0x7767_6874) // 'wght'
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .variation: [wghtAxis: NSNumber(value: Double(weight))]
        ])
        return NSFont(descriptor: descriptor, size: size)
    }
}

extension Font {
    /// Archivo, for body and UI text. `weight` uses the CSS scale (400 regular, 500 medium).
    static func sift(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        if let font = SiftFonts.nsFont(SiftFonts.ui, size: size, weight: weight) { return Font(font) }
        return .system(size: size, weight: Font.Weight(css: weight))
    }

    /// Archivo Narrow, for page titles, headlines and big numbers.
    static func siftDisplay(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        if let font = SiftFonts.nsFont(SiftFonts.display, size: size, weight: weight) { return Font(font) }
        return .system(size: size, weight: Font.Weight(css: weight)).width(.condensed)
    }

    /// Chivo Mono, for sizes, paths, counts and shortcut hints.
    static func siftMono(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        if let font = SiftFonts.nsFont(SiftFonts.mono, size: size, weight: weight) { return Font(font) }
        return .system(size: size, weight: Font.Weight(css: weight), design: .monospaced)
    }
}

private extension Font.Weight {
    init(css: CGFloat) {
        switch css {
        case ..<350: self = .light
        case ..<450: self = .regular
        case ..<550: self = .medium
        case ..<650: self = .semibold
        default: self = .bold
        }
    }
}
