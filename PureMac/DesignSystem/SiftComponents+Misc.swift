import SwiftUI

// Sift components derived from the designed screens for screens that have no
// design of their own (App updates, Leftovers, onboarding, sheets).

// MARK: - Screen header with a description line

/// The Installers header: eyebrow, 40 pt title and a 13 pt description on the
/// left, actions on the right, bottom-aligned.
struct SiftScreenHeader<Trailing: View>: View {
    let title: Text
    var eyebrow: Text?
    var subtitle: Text?
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
                if let eyebrow { eyebrow.siftStyle(.label).lineLimit(1) }
                title.siftStyle(.pageTitle).lineLimit(1)
                if let subtitle {
                    subtitle.siftStyle(.body).fixedSize(horizontal: false, vertical: true)
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

// MARK: - Notice banner

/// The Uninstaller's "Quit Docker before removing" banner, in any tone.
struct SiftNoticeBanner<Accessory: View>: View {
    let text: Text
    var icon: SiftIcon
    var tone: SiftTone
    @ViewBuilder var accessory: Accessory

    init(_ text: Text, icon: SiftIcon = .triangleAlert, tone: SiftTone = .warning, @ViewBuilder accessory: () -> Accessory) {
        self.text = text
        self.icon = icon
        self.tone = tone
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            icon.image(16).foregroundStyle(tone.foreground).accessibilityHidden(true)
            text
                .font(.sift(12.5))
                .foregroundStyle(tone == .neutral ? SiftColor.textSecondary : tone.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            accessory
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tone.background))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tone == .warning ? SiftColor.warningStroke : SiftColor.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

extension SiftNoticeBanner where Accessory == EmptyView {
    init(_ text: Text, icon: SiftIcon = .triangleAlert, tone: SiftTone = .warning) {
        self.init(text, icon: icon, tone: tone) { EmptyView() }
    }
}

// MARK: - Selection bar

/// The Installers action bar: a count disc, a summary, then actions. Sits
/// below a list as a 64 pt capsule.
struct SiftSelectionBar<Summary: View, Actions: View>: View {
    let count: Int
    @ViewBuilder var summary: Summary
    @ViewBuilder var actions: Actions

    init(count: Int, @ViewBuilder summary: () -> Summary, @ViewBuilder actions: () -> Actions) {
        self.count = count
        self.summary = summary()
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(verbatim: "\(count)")
                .font(.sift(12, weight: 700))
                .foregroundStyle(count > 0 ? SiftColor.onAccent : SiftColor.textTertiary)
                .frame(minWidth: 28, minHeight: 28)
                .padding(.horizontal, count > 99 ? 4 : 0)
                .background(Capsule(style: .continuous).fill(count > 0 ? SiftColor.accent : SiftColor.track))
                .accessibilityHidden(true)
            summary
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(height: 64)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
    }
}

// MARK: - Table header

/// 36 pt column header row inside a table card (11.5 pt tertiary labels).
struct SiftTableHeader<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 14) { content }
            .font(.sift(11.5))
            .foregroundStyle(SiftColor.textTertiary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .accessibilityHidden(true)
    }
}

// MARK: - Wordmark

/// The rail's "S" tile and SIFT wordmark, for surfaces outside the shell.
struct SiftWordmark: View {
    var tile: CGFloat = 28
    var showsName = true

    var body: some View {
        HStack(spacing: tile * 0.36) {
            Text(verbatim: "S")
                .font(.siftDisplay(tile * 0.57, weight: 700))
                .foregroundStyle(SiftColor.onAccent)
                .frame(width: tile, height: tile)
                .background(RoundedRectangle(cornerRadius: tile * 0.32, style: .continuous).fill(SiftColor.accent))
            if showsName {
                Text(verbatim: "SIFT")
                    .font(.siftDisplay(tile * 0.6))
                    .tracking(tile * 0.086)
                    .foregroundStyle(SiftColor.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Sift"))
    }
}
