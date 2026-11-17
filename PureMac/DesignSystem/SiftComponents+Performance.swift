import AppKit
import SwiftUI

// Pieces used by the Performance and Uninstaller screens. Dark values are the
// design's hexes; light values keep the same hierarchy on white cards.

private func siftDynamic(dark: UInt32, light: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
    })
}

/// The accent mixed toward the card color; follows the Settings accent picker.
private func siftAccentMix(darkAmount: CGFloat, lightAmount: CGFloat) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = AccentStore.current
        let base = dark ? accent.darkBase : accent.lightBase
        return base.mixed(with: dark ? NSColor(hex: 0x14171A) : .white, dark ? darkAmount : lightAmount)
    })
}

extension SiftColor {
    /// Unfilled bars and tracks inside an inset panel (CPU history, battery bars).
    static let chartBar = siftDynamic(dark: 0x2C3237, light: 0xDEDAD2)
    /// Memory: active pages, a half-strength accent.
    static let memoryActive = siftAccentMix(darkAmount: 0.5, lightAmount: 0.45)
    /// Memory: compressed pages.
    static let memoryCompressed = siftDynamic(dark: 0x3F474E, light: 0xA9AFB4)
    /// Memory: legend dot for free memory.
    static let memoryFreeDot = siftDynamic(dark: 0x4A5259, light: 0xC9CDD0)
    /// Stroke around the selected row in a list card.
    static let selectedStroke = siftAccentMix(darkAmount: 0.8, lightAmount: 0.7)
    /// The uninstaller's "quit first" banner.
    static let cautionBackground = siftDynamic(dark: 0x22160F, light: 0xFDF1E8)
    static let cautionStroke = siftDynamic(dark: 0x4A2B18, light: 0xF1C7AB)
    static let cautionText = siftDynamic(dark: 0xF3B48C, light: 0x8F4115)
    static let cautionButton = siftDynamic(dark: 0x3A2214, light: 0xF9DCC7)
}

// MARK: - Metric

/// 48 pt display number with a 13 pt caption on the same baseline ("18%  of 10 cores").
struct SiftMetric: View {
    let value: String
    let caption: Text

    init(_ value: String, caption: Text) {
        self.value = value
        self.caption = caption
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: value)
                .siftStyle(.metric)
                .lineLimit(1)
                .contentTransition(.numericText())
            caption
                .font(.sift(13))
                .foregroundStyle(SiftColor.textSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Legend chip

/// A chip with a colored dot before its label (memory breakdown legend).
struct SiftLegendChip: View {
    let color: Color
    let label: Text
    let value: String
    /// False on narrow cards: the dot carries the meaning, the label stays for VoiceOver.
    var showsLabel = true
    /// Tighter insets for cards a little narrower than the design.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            if showsLabel {
                label.font(.sift(11.5)).foregroundStyle(SiftColor.textTertiary)
            }
            Text(verbatim: value).font(.siftMono(11)).foregroundStyle(SiftColor.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: value))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, compact ? 9 : 12)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
    }
}

// MARK: - Bars

/// A 10 pt bar on the inset-panel track, filled to `fraction`.
struct SiftPanelBar: View {
    let fraction: Double
    var fill: Color = SiftColor.accent

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(SiftColor.chartBar)
                if clamped > 0 {
                    Capsule(style: .continuous)
                        .fill(fill)
                        .frame(width: max(10, proxy.size.width * clamped))
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// The battery charge bar: `count` pills, the first `filled` in the accent.
struct SiftSegmentBar: View {
    let filled: Int
    var count = 20

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index < filled ? SiftColor.accent : SiftColor.chartBar)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Vertical bars for a 0–1 history, oldest first. Missing samples on the left
/// render as short empty bars; the newest bar uses the accent.
struct SiftHistoryBars: View {
    let values: [Double]
    var slots = 30
    var height: CGFloat = 56

    var body: some View {
        let padded = Array(repeating: Double?.none, count: max(0, slots - values.count))
            + values.suffix(slots).map(Optional.some)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(padded.indices, id: \.self) { index in
                let value = padded[index]
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(index == padded.count - 1 && value != nil ? SiftColor.accent : SiftColor.chartBar)
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(value))
            }
        }
        .frame(height: height, alignment: .bottom)
        .animation(SiftMotion.quick, value: values)
        .accessibilityHidden(true)
    }

    private func barHeight(_ value: Double?) -> CGFloat {
        guard let value else { return 4 }
        return max(6, height * CGFloat(min(max(value, 0), 1)))
    }
}

// MARK: - Tag

/// Small capsule naming a kind ("Application", "Caches").
struct SiftTag: View {
    let text: Text
    var accented = false

    var body: some View {
        text
            .font(.sift(11, weight: 500))
            .foregroundStyle(accented ? SiftColor.accent : SiftColor.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule(style: .continuous).fill(accented ? SiftColor.accentTint : SiftColor.track))
    }
}

// MARK: - Inset panel

extension View {
    /// A panel nested in a card with the design's 18 pt corners and no stroke.
    func siftInsetPanel(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SiftColor.control))
    }
}
