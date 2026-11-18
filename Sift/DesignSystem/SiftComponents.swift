import SwiftUI

// Sift components, built to the Pairdraw design ("Sift v2 — Rounded").
// Views compose these instead of styling raw SwiftUI controls.

// MARK: - Text styles

enum SiftTextStyle {
    /// 52 pt Archivo Narrow: the dashboard headline.
    case hero
    /// 40 pt Archivo Narrow: page titles.
    case pageTitle
    /// 48 pt Archivo Narrow: big metrics on cards.
    case metric
    /// 34 pt Archivo Narrow: secondary metrics and detail titles.
    case metricSmall
    /// 16 pt Archivo Narrow medium: sizes in rows.
    case rowValue
    /// 14 pt medium: card titles.
    case cardTitle
    /// 13 pt: body text.
    case body
    /// 13 pt medium: row titles and button labels.
    case bodyStrong
    /// 12 pt tertiary: eyebrows and helper lines.
    case label
    /// 11 pt tertiary: rail section names and small notes.
    case caption
    /// 11 pt mono tertiary: counts and timestamps.
    case mono
    /// 10.5 pt mono tertiary: paths and sub-lines.
    case monoSmall
    /// 12 pt mono primary: sizes in dense lists.
    case monoValue

    var font: Font {
        switch self {
        case .hero: return .siftDisplay(52)
        case .pageTitle: return .siftDisplay(40)
        case .metric: return .siftDisplay(48)
        case .metricSmall: return .siftDisplay(34)
        case .rowValue: return .siftDisplay(16, weight: 500)
        case .cardTitle: return .sift(14, weight: 500)
        case .body: return .sift(13)
        case .bodyStrong: return .sift(13, weight: 500)
        case .label: return .sift(12)
        case .caption: return .sift(11)
        case .mono: return .siftMono(11)
        case .monoSmall: return .siftMono(10.5)
        case .monoValue: return .siftMono(12)
        }
    }

    var color: Color {
        switch self {
        case .hero, .pageTitle, .metric, .metricSmall, .rowValue, .cardTitle, .bodyStrong, .monoValue:
            return SiftColor.textPrimary
        case .body:
            return SiftColor.textSecondary
        case .label, .caption, .mono, .monoSmall:
            return SiftColor.textTertiary
        }
    }

    var tracking: CGFloat {
        switch self {
        case .hero: return -1.4
        case .pageTitle, .metric: return -1
        case .metricSmall: return -0.6
        default: return 0
        }
    }
}

extension View {
    /// Applies a Sift text style's font, color and tracking. A later
    /// `.foregroundStyle` overrides the color.
    func siftStyle(_ style: SiftTextStyle) -> some View {
        font(style.font)
            .foregroundStyle(style.color)
            .tracking(style.tracking)
    }
}

// MARK: - Surfaces

enum SiftSurface {
    /// Top-level card on the window background.
    case card
    /// The dashboard's hero card.
    case hero
    /// A panel nested inside a card.
    case inset

    var fill: Color {
        switch self {
        case .card, .hero: return SiftColor.card
        case .inset: return SiftColor.control
        }
    }

    var stroke: Color {
        switch self {
        case .card, .hero: return SiftColor.stroke
        case .inset: return SiftColor.controlStroke
        }
    }

    var radius: CGFloat {
        switch self {
        case .hero: return SiftRadius.hero
        case .card: return SiftRadius.card
        case .inset: return SiftRadius.panel
        }
    }

    var padding: CGFloat {
        switch self {
        case .hero: return SiftSpacing.heroPadding
        case .card: return SiftSpacing.cardPadding
        case .inset: return 18
        }
    }
}

extension View {
    /// Wraps the view in a Sift surface: fill, 1 px stroke, continuous corners
    /// and the surface's padding (pass `padding: 0` for edge-to-edge content).
    func siftSurface(_ surface: SiftSurface = .card, padding: CGFloat? = nil) -> some View {
        self
            .padding(padding ?? surface.padding)
            .background(
                RoundedRectangle(cornerRadius: surface.radius, style: .continuous).fill(surface.fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: surface.radius, style: .continuous)
                    .strokeBorder(surface.stroke, lineWidth: 1)
            )
    }
}

// MARK: - Page header

/// Eyebrow + 40 pt title on the left, actions on the right, bottom-aligned.
struct SiftPageHeader<Trailing: View>: View {
    let eyebrow: Text?
    let title: Text
    @ViewBuilder var trailing: Trailing

    init(_ title: Text, eyebrow: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.eyebrow = eyebrow
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow { eyebrow.siftStyle(.label) }
                title.siftStyle(.pageTitle).lineLimit(1)
            }
            Spacer(minLength: 16)
            trailing
        }
        .padding(.top, 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

extension SiftPageHeader where Trailing == EmptyView {
    init(_ title: Text, eyebrow: Text? = nil) {
        self.init(title, eyebrow: eyebrow) { EmptyView() }
    }
}

/// Card heading: 14 pt title with an optional mono note on the right.
struct SiftCardHeader<Accessory: View>: View {
    let title: Text
    var icon: SiftIcon?
    @ViewBuilder var accessory: Accessory

    init(_ title: Text, icon: SiftIcon? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.icon = icon
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                SiftIconTile(icon: icon, size: 30)
            }
            title.siftStyle(.cardTitle)
            Spacer(minLength: 8)
            accessory
        }
    }
}

extension SiftCardHeader where Accessory == EmptyView {
    init(_ title: Text, icon: SiftIcon? = nil) {
        self.init(title, icon: icon) { EmptyView() }
    }
}

// MARK: - Buttons

enum SiftButtonKind {
    /// Accent fill; the one main action on a screen.
    case primary
    /// Raised control fill with a stroke.
    case secondary
    /// Warning-tinted, for actions that delete without the Trash.
    case destructive
    /// No fill until hovered.
    case quiet
}

struct SiftButtonStyle: ButtonStyle {
    var kind: SiftButtonKind = .secondary
    /// 38 pt (regular) or 32 pt (compact) tall pill.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        SiftButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

private struct SiftButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: SiftButtonKind
    let compact: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.sift(compact ? 12.5 : 13, weight: 500))
            .foregroundStyle(foreground)
            .labelStyle(SiftButtonLabelStyle())
            .padding(.horizontal, compact ? 12 : 16)
            .frame(height: compact ? 32 : 38)
            .background(Capsule(style: .continuous).fill(fill))
            .overlay(Capsule(style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .onHover { hovering = $0 }
            .animation(SiftMotion.quick, value: hovering)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return SiftColor.onAccent
        case .destructive: return SiftColor.warning
        case .secondary, .quiet: return SiftColor.textPrimary
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return hovering ? SiftColor.accentHover : SiftColor.accent
        case .secondary: return hovering ? SiftColor.selected : SiftColor.control
        case .destructive: return SiftColor.warningBackground
        case .quiet: return hovering ? SiftColor.control : .clear
        }
    }

    private var stroke: Color {
        switch kind {
        case .primary, .quiet: return .clear
        case .secondary: return SiftColor.controlStroke
        case .destructive: return hovering ? SiftColor.warning : SiftColor.warningStroke
        }
    }
}

/// Icon-before-title with the design's 8 pt gap; icons follow the label color.
private struct SiftButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.font(.system(size: 13.5))
            configuration.title
        }
    }
}

extension ButtonStyle where Self == SiftButtonStyle {
    static var siftPrimary: SiftButtonStyle { SiftButtonStyle(kind: .primary) }
    static var siftSecondary: SiftButtonStyle { SiftButtonStyle(kind: .secondary) }
    static var siftDestructive: SiftButtonStyle { SiftButtonStyle(kind: .destructive) }
    static var siftQuiet: SiftButtonStyle { SiftButtonStyle(kind: .quiet, compact: true) }
    static func sift(_ kind: SiftButtonKind, compact: Bool = false) -> SiftButtonStyle {
        SiftButtonStyle(kind: kind, compact: compact)
    }
}

/// A keyboard shortcut hint ("⌘R"). On an accent button pass `onAccent: true`.
struct SiftKeyHint: View {
    let keys: String
    var onAccent = false

    init(_ keys: String, onAccent: Bool = false) {
        self.keys = keys
        self.onAccent = onAccent
    }

    var body: some View {
        Text(verbatim: keys)
            .font(.siftMono(10.5))
            .foregroundStyle(onAccent ? SiftColor.onAccentMuted : SiftColor.textTertiary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(onAccent ? SiftColor.accentPressed : SiftColor.track)
            )
    }
}

// MARK: - Chips, badges, pills

/// Label + mono value capsule, as in the dashboard's storage chips.
struct SiftChip: View {
    let label: Text
    let value: String

    init(_ label: Text, value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(spacing: 8) {
            label.font(.sift(11.5)).foregroundStyle(SiftColor.textTertiary)
            Text(verbatim: value).font(.siftMono(11)).foregroundStyle(SiftColor.textSecondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
    }
}

/// Small mono count, as in the rail's per-category sizes.
struct SiftBadge: View {
    let text: String
    var highlighted = false

    init(_ text: String, highlighted: Bool = false) {
        self.text = text
        self.highlighted = highlighted
    }

    var body: some View {
        Text(verbatim: text)
            .font(.siftMono(10.5))
            .foregroundStyle(highlighted ? SiftColor.accent : SiftColor.textTertiary)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule(style: .continuous).fill(highlighted ? SiftColor.accentTint : SiftColor.badge))
    }
}

enum SiftTone {
    case neutral, accent, success, warning, info

    var foreground: Color {
        switch self {
        case .neutral: return SiftColor.textSecondary
        case .accent: return SiftColor.accent
        case .success: return SiftColor.success
        case .warning: return SiftColor.warning
        case .info: return SiftColor.info
        }
    }

    var background: Color {
        switch self {
        case .neutral: return SiftColor.control
        case .accent: return SiftColor.accentTint
        case .success: return SiftColor.successBackground
        case .warning: return SiftColor.warningBackground
        case .info: return SiftColor.infoBackground
        }
    }
}

/// A 6 pt status dot.
struct SiftDot: View {
    var tone: SiftTone = .success

    var body: some View {
        Circle().fill(tone.foreground).frame(width: 6, height: 6)
    }
}

/// Dot + label on a tinted capsule ("Charging", "1 not loading").
struct SiftStatusPill: View {
    let text: Text
    var tone: SiftTone = .success
    var showsDot = true

    init(_ text: Text, tone: SiftTone = .success, showsDot: Bool = true) {
        self.text = text
        self.tone = tone
        self.showsDot = showsDot
    }

    var body: some View {
        HStack(spacing: 6) {
            if showsDot { SiftDot(tone: tone) }
            text.font(.sift(11)).foregroundStyle(tone.foreground).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule(style: .continuous).fill(tone.background))
    }
}

// MARK: - Icon tile

struct SiftIconTile: View {
    let icon: SiftIcon
    var tone: SiftTone = .neutral
    var size: CGFloat = 32

    var body: some View {
        icon.image(size * 0.47)
            .foregroundStyle(tone == .neutral ? SiftColor.textSecondary : tone.foreground)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: SiftRadius.tile, style: .continuous)
                    .fill(tone == .neutral ? SiftColor.control : tone.background)
            )
    }
}

// MARK: - Rows

extension View {
    /// The list-row treatment: 14 pt corners, control fill when hovered or
    /// selected, accent wash when `accented` (a checked row).
    func siftRowBackground(selected: Bool = false, accented: Bool = false, radius: CGFloat = SiftRadius.row) -> some View {
        modifier(SiftRowBackground(selected: selected, accented: accented, radius: radius))
    }
}

private struct SiftRowBackground: ViewModifier {
    let selected: Bool
    let accented: Bool
    let radius: CGFloat
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(accented ? SiftColor.accentWash : (selected || hovering) ? SiftColor.control : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
    }
}

// MARK: - Toggles

/// 40×24 switch. The label, if any, sits on the leading side.
struct SiftSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SiftSwitch(configuration: configuration)
    }
}

private struct SiftSwitch: View {
    let configuration: ToggleStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 12) {
            configuration.label
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(track)
                    .frame(width: 40, height: 24)
                Circle()
                    .fill(configuration.isOn ? SiftColor.onAccent : (hovering ? SiftColor.textSecondary : SiftColor.textTertiary))
                    .frame(width: 18, height: 18)
                    .padding(3)
            }
            .animation(SiftMotion.snappy, value: configuration.isOn)
            .onHover { hovering = $0 }
            .onTapGesture { configuration.isOn.toggle() }
            .opacity(isEnabled ? 1 : 0.45)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private var track: Color {
        if configuration.isOn { return hovering ? SiftColor.accentHover : SiftColor.accent }
        return hovering ? SiftColor.switchOffHover : SiftColor.switchOff
    }
}

/// 20×20 checkbox with 7 pt corners. The label, if any, follows the box.
struct SiftCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SiftCheckbox(configuration: configuration)
    }
}

private struct SiftCheckbox: View {
    let configuration: ToggleStyleConfiguration
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: SiftRadius.checkbox, style: .continuous)
                    .fill(fill)
                RoundedRectangle(cornerRadius: SiftRadius.checkbox, style: .continuous)
                    .strokeBorder(configuration.isOn ? .clear : (hovering ? SiftColor.accent : SiftColor.checkboxStroke), lineWidth: 1.5)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(SiftColor.onAccent)
                }
            }
            .frame(width: 20, height: 20)
            .onHover { hovering = $0 }
            configuration.label
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
        }
    }

    private var fill: Color {
        if configuration.isOn { return hovering ? SiftColor.accentHover : SiftColor.accent }
        return hovering ? SiftColor.control : SiftColor.checkboxFill
    }
}

extension ToggleStyle where Self == SiftSwitchStyle {
    static var siftSwitch: SiftSwitchStyle { SiftSwitchStyle() }
}

extension ToggleStyle where Self == SiftCheckboxStyle {
    static var siftCheckbox: SiftCheckboxStyle { SiftCheckboxStyle() }
}

// MARK: - Segmented control

/// Pill segmented control (Appearance: Dark / Light / System).
struct SiftSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: Text)]

    init(selection: Binding<Value>, options: [(value: Value, label: Text)]) {
        _selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                SiftSegment(
                    label: options[index].label,
                    isOn: options[index].value == selection
                ) { selection = options[index].value }
            }
        }
        .padding(4)
        .background(Capsule(style: .continuous).fill(SiftColor.window))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
    }
}

private struct SiftSegment: View {
    let label: Text
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label
                .font(.sift(12.5, weight: isOn ? 400 : 500))
                .foregroundStyle(isOn ? SiftColor.onAccent : (hovering ? SiftColor.textPrimary : SiftColor.textSecondary))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule(style: .continuous).fill(fill))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var fill: Color {
        if isOn { return hovering ? SiftColor.accentHover : SiftColor.accent }
        return hovering ? SiftColor.selected : .clear
    }
}

// MARK: - Slider and meter

/// 6 pt track with a 22 pt ringed thumb.
struct SiftSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - 22, 1)
            let fraction = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, .ulpOfOne)
            ZStack(alignment: .leading) {
                Capsule().fill(SiftColor.controlStroke).frame(height: 6).padding(.horizontal, 11)
                Capsule().fill(SiftColor.accent).frame(width: max(6, width * fraction), height: 6).padding(.leading, 11)
                Circle()
                    .fill(SiftColor.textPrimary)
                    .overlay(Circle().strokeBorder(SiftColor.accent, lineWidth: 4))
                    .background(Circle().fill(SiftColor.accent.opacity(0.2)).padding(-6))
                    .frame(width: 22, height: 22)
                    .offset(x: width * fraction)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let raw = range.lowerBound + Double((drag.location.x - 11) / width) * (range.upperBound - range.lowerBound)
                let stepped = (raw / step).rounded() * step
                value = min(max(stepped, range.lowerBound), range.upperBound)
            })
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(value))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// A thin progress track (6 pt by default) filled to `fraction`.
struct SiftMeterBar: View {
    let fraction: Double
    var fill: Color = SiftColor.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SiftColor.track)
                Capsule()
                    .fill(fill)
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * min(max(fraction, 0), 1)) : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"))
    }
}

// MARK: - Search field

struct SiftSearchField: View {
    @Binding var text: String
    let prompt: Text
    var shortcut: String? = "⌘F"
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            SiftIcon.search.image(15).foregroundStyle(SiftColor.textTertiary)
            TextField(text: $text, prompt: prompt.foregroundColor(SiftColor.textTertiary)) { prompt }
                .textFieldStyle(.plain)
                .font(.sift(13))
                .foregroundStyle(SiftColor.textPrimary)
                .focused($focused)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    SiftIcon.x.image(13).foregroundStyle(SiftColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            } else if let shortcut {
                Text(verbatim: shortcut)
                    .font(.siftMono(10.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(SiftColor.track))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Capsule(style: .continuous).fill(SiftColor.card))
        .overlay(Capsule(style: .continuous).strokeBorder(focused ? SiftColor.accent : SiftColor.controlStroke, lineWidth: 1))
        .background {
            if shortcut == "⌘F" {
                Button("") { focused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Empty and footnote

/// Small icon + tertiary sentence, used for card footnotes ("Nothing is deleted without review").
struct SiftFootnote: View {
    let icon: SiftIcon
    let text: Text

    init(_ text: Text, icon: SiftIcon = .info) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 8) {
            icon.image(14).foregroundStyle(SiftColor.textTertiary)
            text.font(.sift(12)).foregroundStyle(SiftColor.textTertiary)
        }
    }
}
