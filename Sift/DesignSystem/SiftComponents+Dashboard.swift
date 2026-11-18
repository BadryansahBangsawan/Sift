import AppKit
import SwiftUI

// Pieces shared by the Overview dashboard and the cleanup screens, built to
// the Pairdraw design ("Dashboard" and "Installers" frames).

// MARK: - Formatting

enum SiftFormat {
    /// Byte counts as the design shows them ("41.9 GB", "612 MB", "0 KB").
    static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB, .usePB]
        return formatter.string(fromByteCount: max(0, count))
    }

    /// "3 days ago", "yesterday", "last month".
    static func relative(_ date: Date, to now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    /// "12 min ago", for the compact "scanned …" status lines.
    static func relativeShort(_ date: Date, to now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return String(localized: "just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    static func count(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

// MARK: - Toolbar pill

/// The 40 pt filter pills on a cleanup screen ("Any size", "Newest first").
/// `active` gives the accent-washed look of an applied preset.
struct SiftPillStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        SiftPillBody(configuration: configuration, active: active)
    }
}

private struct SiftPillBody: View {
    let configuration: ButtonStyleConfiguration
    let active: Bool
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.sift(13, weight: 500))
            .foregroundStyle(SiftColor.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule(style: .continuous).fill(active ? SiftColor.accentWash : (hovering ? SiftColor.control : SiftColor.card)))
            .overlay(Capsule(style: .continuous).strokeBorder(active ? SiftColor.accentDim : SiftColor.controlStroke, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .onHover { hovering = $0 }
    }
}

// MARK: - Dropdown menu

/// Rounded floating panel for a pill's menu (the design's "Preset popover").
struct SiftMenuPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(8)
        .frame(width: 272)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SiftColor.control))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        .shadow(color: .black.opacity(0.45), radius: 24, y: 20)
    }
}

struct SiftMenuHeader: View {
    let title: Text

    init(_ title: Text) { self.title = title }

    var body: some View {
        title
            .font(.sift(11))
            .foregroundStyle(SiftColor.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SiftMenuDivider: View {
    var body: some View {
        Rectangle().fill(SiftColor.controlStroke).frame(height: 1)
    }
}

/// One 34 pt menu row: a 14 pt leading slot (check mark or icon), the title
/// and an optional mono detail ("2 items").
struct SiftMenuRow: View {
    let title: Text
    var detail: String?
    var checked = false
    var icon: SiftIcon?
    var muted = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if checked {
                        SiftIcon.check.image(14).foregroundStyle(SiftColor.accent)
                    } else if let icon {
                        icon.image(14).foregroundStyle(muted ? SiftColor.textTertiary : SiftColor.textSecondary)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 14, height: 14)
                title
                    .font(.sift(12.5))
                    .foregroundStyle(muted ? SiftColor.textTertiary : SiftColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail {
                    Text(verbatim: detail)
                        .font(.siftMono(10.5))
                        .foregroundStyle(SiftColor.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(checked || (hovering && isEnabled) ? SiftColor.controlStroke : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// Bounds of each pill that can open a menu, so the screen can float the
/// panel above everything else, 8 pt under its pill.
struct SiftMenuAnchorKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [ID: Anchor<CGRect>], nextValue: () -> [ID: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Floats `panel(open)` under the pill registered for `open`, with a
    /// full-size click catcher behind it that closes the menu.
    func siftMenuHost<ID: Hashable, Panel: View>(
        open: Binding<ID?>,
        @ViewBuilder panel: @escaping (ID) -> Panel
    ) -> some View {
        overlayPreferenceValue(SiftMenuAnchorKey<ID>.self) { anchors in
            GeometryReader { proxy in
                if let id = open.wrappedValue, let anchor = anchors[id] {
                    let rect = proxy[anchor]
                    ZStack(alignment: .topLeading) {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { open.wrappedValue = nil }
                        panel(id)
                            .fixedSize()
                            .offset(x: rect.minX, y: rect.maxY + 8)
                            .onExitCommand { open.wrappedValue = nil }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .transition(.opacity)
                }
            }
        }
    }

    /// Registers this pill as the anchor for menu `id`.
    func siftMenuAnchor<ID: Hashable>(_ id: ID) -> some View {
        anchorPreference(key: SiftMenuAnchorKey<ID>.self, value: .bounds) { [id: $0] }
    }
}

// MARK: - Ring

/// The battery card's 84 pt ring: a track and an accent arc from 12 o'clock.
struct SiftRing<Label: View>: View {
    let fraction: Double
    var size: CGFloat = 84
    @ViewBuilder var label: Label

    var body: some View {
        let lineWidth = size * 0.1
        ZStack {
            Circle()
                .stroke(SiftColor.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(SiftColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            label
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
    }
}

// MARK: - Removal review

/// The review sheet shown before removing cleanup items: every item with its
/// size, path and how it will be removed.
struct SiftRemovalReview: View {
    let items: [CleanableItem]
    var disabled = false
    let cancel: () -> Void
    let remove: () -> Void

    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Review removal")
                    .siftStyle(.metricSmall)
                    .accessibilityAddTraits(.isHeader)
                Text("\(items.count) items · \(SiftFormat.bytes(totalSize))")
                    .font(.siftMono(12))
                    .foregroundStyle(SiftColor.accent)
                Text("Files and cleanup actions marked Permanent cannot be undone. Items marked Move to Trash can be recovered until the Trash is emptied.")
                    .siftStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(item.name)
                                    .font(.sift(13, weight: 500))
                                    .foregroundStyle(SiftColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Text(item.formattedSize)
                                    .font(.siftMono(12))
                                    .foregroundStyle(SiftColor.textPrimary)
                            }
                            if !item.path.isEmpty {
                                Text(item.path)
                                    .font(.siftMono(10.5))
                                    .foregroundStyle(SiftColor.textTertiary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(Self.removalMethod(item))
                                .font(.sift(11, weight: 500))
                                .foregroundStyle(SiftColor.textSecondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .siftRowBackground()
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 160, maxHeight: 300)
            .background(RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous).fill(SiftColor.window))
            .overlay(RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous).strokeBorder(SiftColor.stroke, lineWidth: 1))
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .buttonStyle(.siftSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(role: .destructive, action: remove) {
                    Label("Remove \(items.count) items", systemImage: "trash")
                }
                .buttonStyle(.siftDestructive)
                .disabled(items.isEmpty || disabled)
            }
        }
        .padding(24)
        .frame(width: 580)
        .background(SiftColor.card)
    }

    static func removalMethod(_ item: CleanableItem) -> String {
        if item.simctlRuntimeIdentifier != nil {
            return String(localized: "Permanent · Remove simulator runtime")
        }
        if item.isActionItem {
            return String(localized: "Permanent · Run cleanup action")
        }
        if XcodeBuildMCPDerivedDataSupport.isManagedDerivedDataPath(item.path) {
            return String(localized: "Move to Trash")
        }
        if item.movesToTrash {
            return String(localized: "Move to Trash")
        }
        return String(localized: "Permanent · Delete files")
    }
}

// MARK: - Category groups

extension CleaningCategory {
    /// The rail row a category belongs to: the group's lead for System junk
    /// (`.systemJunk`) and Developer caches (`.xcodeJunk`), else itself.
    var cleanupLead: CleaningCategory {
        if Self.systemJunkGroup.contains(self) { return .systemJunk }
        if Self.developerCaches.contains(self) { return .xcodeJunk }
        return self
    }

    /// Every category a cleanup screen for this category lists, limited to
    /// the ones a scan can measure.
    var cleanupMembers: [CleaningCategory] {
        let group: [CleaningCategory]
        switch cleanupLead {
        case .systemJunk: group = Self.systemJunkGroup
        case .xcodeJunk: group = Self.developerCaches
        default: return [self]
        }
        let measurable = group.filter(Self.smartScanCategories.contains)
        return measurable.isEmpty ? [self] : measurable
    }

    var isCleanupGroup: Bool { cleanupMembers.count > 1 }

    /// Sentence-case screen title, matching the rail.
    var cleanupTitleKey: String {
        switch cleanupLead {
        case .systemJunk: return "System junk"
        case .xcodeJunk: return "Developer caches"
        case .installers: return "Installers"
        case .largeFiles: return "Large & old files"
        case .mailAttachments: return "Mail files"
        case .trash: return "Trash"
        case .aiApps: return "AI tools"
        default: return rawValue
        }
    }

    var cleanupTitle: LocalizedStringKey {
        LocalizedStringKey(cleanupTitleKey)
    }

    var cleanupDescription: LocalizedStringKey {
        switch cleanupLead {
        case .systemJunk: return "System and app caches, logs, and temporary files"
        case .xcodeJunk: return "Xcode, Homebrew, npm, and Docker caches"
        case .aiApps: return "Caches, logs, and optional chat history of AI apps and coding agents"
        default: return LocalizedStringKey(description)
        }
    }

    var siftIcon: SiftIcon {
        switch cleanupLead {
        case .systemJunk: return .trash2
        case .xcodeJunk: return .codeXml
        case .installers: return .disc3
        case .largeFiles: return .fileArchive
        case .mailAttachments: return .mail
        case .trash: return .trash
        case .aiApps: return .sparkles
        default: return .file
        }
    }
}
