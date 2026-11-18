import SwiftUI

// Components shared by the tool screens (Space explorer, Duplicates, Similar
// photos, Apple features, Protection). These screens have no design of their
// own; each piece reuses the grammar of a designed screen, noted per type.

// MARK: - Page header with a subtitle

/// The Installers header: eyebrow, 40 pt title and a 13 pt subtitle on the
/// left, actions on the right, bottom-aligned.
struct SiftToolHeader<Trailing: View>: View {
    let title: Text
    let eyebrow: Text?
    let subtitle: Text?
    @ViewBuilder var trailing: Trailing

    init(_ title: Text, eyebrow: Text? = nil, subtitle: Text? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                if let eyebrow { eyebrow.siftStyle(.label) }
                title.siftStyle(.pageTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    subtitle.siftStyle(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) { trailing }
        }
        .padding(.top, 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Empty and message states

/// A card that fills the space below the header with one centered message:
/// an icon tile, a title, a sentence, an optional footnote and actions.
struct SiftEmptyState<Actions: View>: View {
    let icon: SiftIcon
    var tone: SiftTone = .accent
    let title: Text
    let message: Text
    var footnote: Text?
    @ViewBuilder var actions: Actions

    init(
        icon: SiftIcon,
        tone: SiftTone = .accent,
        title: Text,
        message: Text,
        footnote: Text? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.tone = tone
        self.title = title
        self.message = message
        self.footnote = footnote
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 14) {
            SiftIconTile(icon: icon, tone: tone, size: 48)
            VStack(spacing: 6) {
                title.font(.sift(16, weight: 500)).foregroundStyle(SiftColor.textPrimary)
                message.siftStyle(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            if let footnote {
                footnote.siftStyle(.label)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
            HStack(spacing: 8) { actions }
                .padding(.top, 4)
        }
        .padding(SiftSpacing.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
        .siftSurface(.card, padding: 0)
    }
}

extension SiftEmptyState where Actions == EmptyView {
    init(icon: SiftIcon, tone: SiftTone = .accent, title: Text, message: Text, footnote: Text? = nil) {
        self.init(icon: icon, tone: tone, title: title, message: message, footnote: footnote) { EmptyView() }
    }
}

// MARK: - Progress

/// A 6 pt track. With a fraction it fills like `SiftMeterBar`; without one an
/// accent segment sweeps across (held still when Reduce Motion is on).
struct SiftProgressBar: View {
    var fraction: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    var body: some View {
        if let fraction {
            SiftMeterBar(fraction: fraction)
        } else {
            GeometryReader { proxy in
                let width = proxy.size.width
                let segment = max(width * 0.28, 24)
                ZStack(alignment: .leading) {
                    Capsule().fill(SiftColor.track)
                    Capsule()
                        .fill(SiftColor.accent)
                        .frame(width: segment)
                        .offset(x: reduceMotion ? (width - segment) / 2 : -segment + (width + segment) * sweep)
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = 1 }
            }
            .accessibilityHidden(true)
        }
    }
}

/// The scanning card: spinner tile, what is happening, the current item, an
/// optional Stop button, a progress track and a row of count pills.
struct SiftScanningCard<Counts: View>: View {
    let title: Text
    let detail: Text
    var fraction: Double?
    var stop: (() -> Void)?
    @ViewBuilder var counts: Counts

    init(title: Text, detail: Text, fraction: Double? = nil, stop: (() -> Void)? = nil, @ViewBuilder counts: () -> Counts) {
        self.title = title
        self.detail = detail
        self.fraction = fraction
        self.stop = stop
        self.counts = counts()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: SiftRadius.tile, style: .continuous).fill(SiftColor.accentTint))
                VStack(alignment: .leading, spacing: 3) {
                    title.siftStyle(.cardTitle)
                    detail.siftStyle(.monoSmall)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let stop {
                    Button("Stop", action: stop)
                        .buttonStyle(.sift(.secondary, compact: true))
                }
            }
            SiftProgressBar(fraction: fraction)
            HStack(spacing: 8) { counts }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .siftSurface(.card)
    }
}

/// A neutral or toned capsule holding an already-localized count ("120 items").
struct SiftCountPill: View {
    let text: String
    var tone: SiftTone = .neutral

    init(_ text: String, tone: SiftTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(verbatim: text)
            .font(.siftMono(11))
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule(style: .continuous).fill(tone.background))
    }
}

// MARK: - Path bar

/// The folder being inspected: optional leading control, folder icon, the path
/// in Chivo Mono, then actions. A slim card with fully rounded ends.
struct SiftPathBar<Leading: View, Actions: View>: View {
    let path: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var actions: Actions

    init(path: String, @ViewBuilder leading: () -> Leading, @ViewBuilder actions: () -> Actions) {
        self.path = path
        self.leading = leading()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 10) {
            leading
            SiftIcon.folderOpen.image(15)
                .foregroundStyle(SiftColor.accent)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: SiftRadius.tile, style: .continuous).fill(SiftColor.accentTint))
                .accessibilityHidden(true)
            Text(verbatim: path)
                .font(.siftMono(12))
                .foregroundStyle(SiftColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            actions
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background(Capsule(style: .continuous).fill(SiftColor.card))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.stroke, lineWidth: 1))
    }
}

extension SiftPathBar where Leading == EmptyView {
    init(path: String, @ViewBuilder actions: () -> Actions) {
        self.init(path: path, leading: { EmptyView() }, actions: actions)
    }
}

// MARK: - Notice banner

/// The Uninstaller's warning banner, also used in the info tone.
struct SiftNotice<Accessory: View>: View {
    let icon: SiftIcon
    var tone: SiftTone = .warning
    let title: Text?
    let message: Text
    @ViewBuilder var accessory: Accessory

    init(icon: SiftIcon, tone: SiftTone = .warning, title: Text? = nil, message: Text, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon
        self.tone = tone
        self.title = title
        self.message = message
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: title == nil ? .center : .top, spacing: 12) {
            icon.image(16)
                .foregroundStyle(tone.foreground)
                .padding(.top, title == nil ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    title.font(.sift(13, weight: 500)).foregroundStyle(SiftColor.textPrimary)
                }
                message.font(.sift(12.5))
                    .foregroundStyle(title == nil ? tone.foreground : SiftColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tone.background))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tone == .warning ? SiftColor.warningStroke : tone.foreground.opacity(0.22), lineWidth: 1)
        )
    }
}

extension SiftNotice where Accessory == EmptyView {
    init(icon: SiftIcon, tone: SiftTone = .warning, title: Text? = nil, message: Text) {
        self.init(icon: icon, tone: tone, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Stat

/// A Performance-card metric: 34 pt Archivo Narrow value with a label beside it.
struct SiftStat: View {
    let value: String
    let label: Text

    init(_ value: String, label: Text) {
        self.value = value
        self.label = label
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: value).siftStyle(.metricSmall).lineLimit(1)
            label.font(.sift(13)).foregroundStyle(SiftColor.textSecondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Grouped rows

/// The 1 pt rule between grouped rows, inset like the Settings groups.
struct SiftRowDivider: View {
    var inset: CGFloat = 18

    var body: some View {
        Rectangle()
            .fill(SiftColor.controlStroke)
            .frame(height: 1)
            .padding(.horizontal, inset)
    }
}

/// Header row with a turning chevron; the content slides in below.
struct SiftDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        SiftDisclosure(configuration: configuration)
    }
}

private struct SiftDisclosure: View {
    let configuration: DisclosureGroupStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : SiftMotion.snappy) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SiftIcon.chevronDown.image(14)
                        .foregroundStyle(SiftColor.textTertiary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
    }
}

extension DisclosureGroupStyle where Self == SiftDisclosureStyle {
    static var sift: SiftDisclosureStyle { SiftDisclosureStyle() }
}
