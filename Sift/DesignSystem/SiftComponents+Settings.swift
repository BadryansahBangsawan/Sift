import AppKit
import SwiftUI

// Settings building blocks from the Pairdraw "Settings" frame: grouped inset
// cards of rows, path chips, value boxes, dropdowns and accent swatches.

// MARK: - Colors

extension SiftColor {
    /// Accent mixed halfway into the window color: the value box and the
    /// dashed "Add folder" outline (#6E5A1C for brass on dark).
    static let accentStroke = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = AccentStore.current
        return dark
            ? accent.darkBase.mixed(with: NSColor(hex: 0x0D0F11), 0.5)
            : accent.lightBase.mixed(with: .white, 0.5)
    })
}

extension SiftAccent {
    /// The swatch color, matching what the accent resolves to in each appearance.
    var swatch: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkBase : lightBase
        })
    }
}

// MARK: - Sections and rows

/// 13 pt medium section name with an optional tertiary note on the right.
struct SiftSettingsLabel: View {
    let title: Text
    var note: Text?

    var body: some View {
        HStack(spacing: 8) {
            title
                .font(.sift(13, weight: 500))
                .foregroundStyle(SiftColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if let note {
                note.font(.sift(11.5)).foregroundStyle(SiftColor.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// An inset card (control fill, 20 pt corners) holding rows separated by
/// 1 pt dividers. Pass rows separated with `SiftSettingsDivider()`.
struct SiftSettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .siftSurface(.inset, padding: 0)
    }
}

/// The 1 pt rule between rows, inset 18 pt from both card edges.
struct SiftSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(SiftColor.controlStroke)
            .frame(height: 1)
            .padding(.horizontal, 18)
    }
}

/// Title (13.5 medium) and sub-line (12 tertiary) on the left, control on the right.
struct SiftSettingsRow<Control: View>: View {
    let title: Text
    var detail: Text?
    @ViewBuilder var control: Control

    init(_ title: Text, detail: Text? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                title
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                if let detail {
                    detail
                        .font(.sift(12))
                        .foregroundStyle(SiftColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

extension SiftSettingsRow where Control == EmptyView {
    init(_ title: Text, detail: Text? = nil) {
        self.init(title, detail: detail) { EmptyView() }
    }
}

/// A switch row: the whole row's title labels the switch for VoiceOver.
struct SiftSettingsToggleRow: View {
    let title: Text
    var detail: Text?
    @Binding var isOn: Bool

    init(_ title: Text, detail: Text? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        SiftSettingsRow(title, detail: detail) {
            // The switch style draws its label, so pass none and name it for VoiceOver.
            Toggle(isOn: $isOn) { EmptyView() }
                .toggleStyle(.siftSwitch)
                .accessibilityLabel(title)
        }
    }
}

// MARK: - Status pill

/// Check + label on a tinted capsule ("Changes apply immediately").
struct SiftCheckPill: View {
    let text: Text
    var tone: SiftTone = .success
    var icon: SiftIcon = .check

    var body: some View {
        HStack(spacing: 6) {
            icon.image(12)
            text.font(.sift(11, weight: 500)).lineLimit(1)
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule(style: .continuous).fill(tone.background))
    }
}

// MARK: - Value controls

/// The 92×36 mono value box beside a slider ("100 MB").
struct SiftValueBox: View {
    let value: String
    let unit: Text

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: value).font(.siftMono(13)).foregroundStyle(SiftColor.textPrimary)
            unit.font(.sift(11)).foregroundStyle(SiftColor.textTertiary)
        }
        .siftLeftToRightValue()
        .frame(minWidth: 92, minHeight: 36)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SiftColor.window))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SiftColor.accentStroke, lineWidth: 1))
    }
}

/// Minus / value / plus in the value-box shape, for small integer counts.
struct SiftStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let unit: Text

    var body: some View {
        HStack(spacing: 8) {
            button(.minus, enabled: value > range.lowerBound) { value = max(range.lowerBound, value - step) }
                .accessibilityLabel(Text("Decrease"))
            HStack(spacing: 4) {
                Text(verbatim: "\(value)").font(.siftMono(13)).foregroundStyle(SiftColor.textPrimary)
                unit.font(.sift(11)).foregroundStyle(SiftColor.textTertiary)
            }
            .frame(minWidth: 64)
            button(.plus, enabled: value < range.upperBound) { value = min(range.upperBound, value + step) }
                .accessibilityLabel(Text("Increase"))
        }
        .padding(.horizontal, 7)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SiftColor.window))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private enum Glyph { case minus, plus }

    private func button(_ glyph: Glyph, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph == .minus ? "minus" : "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SiftColor.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(SiftColor.track))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// A capsule that opens a native menu of options; the current one is checked.
struct SiftDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    @State private var hovering = false

    init(selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) {
        _selection = selection
        self.options = options
        self.title = title
    }

    var body: some View {
        Button(action: present) {
            HStack(spacing: 8) {
                Text(verbatim: title(selection))
                    .font(.sift(12.5))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                SiftIcon.chevronDown.image(12).foregroundStyle(SiftColor.textTertiary)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(height: 32)
            .background(Capsule(style: .continuous).fill(hovering ? SiftColor.selected : SiftColor.window))
            .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityValue(Text(verbatim: title(selection)))
    }

    private func present() {
        let binding = $selection
        let menu = NSMenu()
        for option in options {
            let item = SiftMenuItem(title: title(option)) { binding.wrappedValue = option }
            item.state = option == selection ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSEvent.mouseLocation, in: nil)
    }
}

private final class SiftMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

// MARK: - Path chips

/// Wraps children onto new lines from the leading edge, like CSS `flex-wrap`.
/// SwiftUI mirrors a custom `Layout`'s placements for a right-to-left layout,
/// so the rows need no direction of their own.
struct SiftFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width && !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// A folder path capsule with a remove button.
struct SiftPathChip: View {
    let path: String
    let removeLabel: Text
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SiftIcon.folder.image(14).foregroundStyle(SiftColor.textSecondary)
            Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
                .font(.siftMono(11.5))
                .foregroundStyle(SiftColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 360, alignment: .leading)
                .siftLeftToRightValue()
                .help(path)
            Button(action: remove) {
                SiftIcon.x.image(12)
                    .foregroundStyle(SiftColor.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(SiftColor.track))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(removeLabel)
            .accessibilityLabel(removeLabel)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(Capsule(style: .continuous).fill(SiftColor.window))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
    }
}

/// The dashed accent capsule that adds an entry ("+ Add folder").
struct SiftDashedAddButton: View {
    let title: Text
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                SiftIcon.plus.image(14)
                title.font(.sift(12, weight: 500))
            }
            .foregroundStyle(SiftColor.accent)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule(style: .continuous).fill(hovering ? SiftColor.accentWash : .clear))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(hovering ? SiftColor.accent : SiftColor.accentStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Accent swatches

/// The accent picker: 28 pt dots; the selected one is ringed and checked.
struct SiftAccentPicker: View {
    @Binding var selection: SiftAccent

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SiftAccent.allCases) { accent in
                SiftAccentSwatch(accent: accent, isSelected: accent == selection) { selection = accent }
            }
        }
        .frame(height: 40)
    }
}

private struct SiftAccentSwatch: View {
    let accent: SiftAccent
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(accent.swatch, lineWidth: 2)
                    .opacity(isSelected ? 1 : (hovering ? 0.45 : 0))
                Circle()
                    .fill(accent.swatch)
                    .frame(width: isSelected ? 24 : 28, height: isSelected ? 24 : 28)
                if isSelected {
                    SiftIcon.check.image(13).foregroundStyle(SiftColor.onAccent)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(Text(accent.label))
        .accessibilityLabel(Text(accent.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(SiftMotion.quick, value: isSelected)
    }
}
