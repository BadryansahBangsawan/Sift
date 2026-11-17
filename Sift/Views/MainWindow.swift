import SwiftUI

/// The app shell from the Sift design: a floating rail on the left and the
/// selected screen on the right, both inset 12 pt from the window edge.
struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permission = PermissionCoordinator.shared
    @ObservedObject private var accentStore = AccentStore.shared
    @State private var selectedSection: AppSection? = .cleaning(.smartScan)
    @FocusState private var focusedSection: AppSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: SiftSpacing.gutter) {
            SiftRail(
                selection: selectedSection,
                scheduler: appState.scheduler,
                select: selectSection,
                badge: railBadge(for:),
                focusedSection: $focusedSection
            )
            .onMoveCommand(perform: moveSelection)

            detailContainer
        }
        .padding(SiftSpacing.gutter)
        .background(SiftColor.window.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .tint(SiftColor.accent)
        .id(accentStore.accent)
        .frame(minWidth: 1080, minHeight: 700)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appState.checkFullDiskAccess()
            permission.refreshStatus()
        }
        .onChange(of: appState.pendingExternalApp) { app in
            guard app != nil else { return }
            selectSection(.apps)
            appState.pendingExternalApp = nil
        }
        .onChange(of: appState.showUpdateSettings) { showUpdates in
            if showUpdates { selectSection(.settings) }
        }
        .onAppear {
            if appState.showUpdateSettings {
                selectSection(.settings)
            } else if appState.pendingExternalApp != nil {
                selectSection(.apps)
                appState.pendingExternalApp = nil
            } else if let selectedSection {
                focusedSection = selectedSection
            }
        }
        .onChange(of: appState.cleanErrorIsFDAFixable) { isFDAFixable in
            guard isFDAFixable else { return }
            let pending = appState.pendingPermissionRetryItems
            appState.cleanError = nil
            appState.cleanErrorIsFDAFixable = false
            appState.requestFullDiskAccessAndRetry(
                items: pending,
                context: .cleanup(failedCount: pending.count)
            )
        }
        .alert("Couldn't clean everything", isPresented: Binding(
            get: { appState.cleanError != nil && !appState.cleanErrorIsFDAFixable },
            set: { if !$0 { appState.cleanError = nil } }
        )) {
            Button("OK", role: .cancel) { appState.cleanError = nil }
        } message: {
            Text(appState.cleanError ?? "")
        }
        .sheet(isPresented: Binding(
            get: { permission.isRequesting && permission.presentation == .mainWindow },
            set: { if !$0 && permission.presentation == .mainWindow { permission.dismiss(callRetry: false) } }
        )) {
            PermissionSheet()
        }
    }

    // MARK: Navigation

    private func selectSection(_ section: AppSection) {
        selectedSection = section
        focusedSection = section
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let sections = SiftRail.orderedSections
        let current = focusedSection ?? selectedSection
        let currentIndex = current.flatMap(sections.firstIndex(of:))
        switch direction {
        case .up:
            selectSection(sections[max(0, (currentIndex ?? sections.count) - 1)])
        case .down:
            selectSection(sections[min(sections.count - 1, (currentIndex ?? -1) + 1)])
        default:
            return
        }
    }

    /// Rail badges show gigabytes without a unit ("28.4"), as in the design.
    private func railBadge(for item: SiftRail.Item) -> String? {
        let size = item.categories.reduce(Int64(0)) { total, category in
            total + (appState.categoryResults[category]?.totalSize ?? 0)
        }
        guard size >= 50_000_000 else { return nil }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: Double(size) / 1_000_000_000))
    }

    // MARK: Detail

    private var detailContainer: some View {
        VStack(spacing: SiftSpacing.gutter) {
            if selectedSection != .settings && !appState.hasFullDiskAccess && !appState.fdaBannerDismissed {
                accessBanner
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
            detailView
                .id(selectedSection)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selectedSection)
        .animation(reduceMotion ? nil : SiftMotion.snappy, value: appState.fdaBannerDismissed)
        .animation(reduceMotion ? nil : SiftMotion.snappy, value: appState.hasFullDiskAccess)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .apps:
            AppListView()
        case .orphans:
            OrphanListView()
        case .spaceExplorer:
            SpaceExplorerView()
        case .duplicates:
            DuplicateFinderView()
        case .similarPhotos:
            SimilarPhotosView()
        case .protection:
            ProtectionView()
        case .performance:
            PerformanceView()
        case .appleFeatures:
            AppleFeaturesView()
        case .appUpdates:
            AppUpdatesView()
        case .settings:
            SettingsView()
        case .cleaning(let category):
            if category == .smartScan {
                DashboardView { selectSection($0) }
            } else {
                CategoryDetailView(category: category)
            }
        case nil:
            EmptyStateView(
                "Sift",
                systemImage: "internaldrive",
                description: "Select a tool from the sidebar."
            )
        }
    }

    private var accessBanner: some View {
        HStack(spacing: 12) {
            SiftIconTile(icon: .lockKeyhole, tone: .warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Full Disk Access is off")
                    .siftStyle(.bodyStrong)
                Text("Protected caches and app containers will be skipped.")
                    .siftStyle(.label)
            }
            Spacer()
            Button("Set up") {
                permission.requestAccess(context: .general) {
                    appState.checkFullDiskAccess()
                }
            }
            .buttonStyle(.siftPrimary)
            Button {
                appState.fdaBannerDismissed = true
            } label: {
                SiftIcon.x.image(14).foregroundStyle(SiftColor.textTertiary)
            }
            .buttonStyle(.siftQuiet)
            .help("Dismiss")
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous).fill(SiftColor.warningBackground))
        .overlay(RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous).strokeBorder(SiftColor.warningStroke, lineWidth: 1))
    }
}

// MARK: - Rail

struct SiftRail: View {
    struct Item: Identifiable {
        let section: AppSection
        let label: LocalizedStringKey
        let icon: SiftIcon
        /// Categories whose scan sizes feed this item's badge.
        var categories: [CleaningCategory] = []
        var id: AppSection { section }
    }

    static let primaryItems: [Item] = [
        Item(section: .cleaning(.smartScan), label: "Overview", icon: .layoutGrid),
        Item(section: .performance, label: "Performance", icon: .activity),
        Item(section: .apps, label: "Uninstaller", icon: .packageMinus)
    ]

    /// Cleanup groups fold the finer scan categories into the design's five rows.
    static let cleanupItems: [Item] = [
        Item(section: .cleaning(.systemJunk), label: "System junk", icon: .trash2,
             categories: CleaningCategory.systemJunkGroup.filter(CleaningCategory.scannable.contains)),
        Item(section: .cleaning(.xcodeJunk), label: "Developer caches", icon: .codeXml,
             categories: CleaningCategory.developerCaches.filter(CleaningCategory.scannable.contains)),
        Item(section: .cleaning(.installers), label: "Installers", icon: .disc3, categories: [.installers]),
        Item(section: .cleaning(.largeFiles), label: "Large & old files", icon: .fileArchive, categories: [.largeFiles]),
        Item(section: .cleaning(.mailAttachments), label: "Mail files", icon: .mail, categories: [.mailAttachments]),
        Item(section: .cleaning(.trash), label: "Trash", icon: .trash, categories: [.trash])
    ]

    static let toolItems: [Item] = [
        Item(section: .spaceExplorer, label: "Space explorer", icon: .chartPie),
        Item(section: .duplicates, label: "Duplicates", icon: .copy),
        Item(section: .similarPhotos, label: "Similar photos", icon: .images),
        Item(section: .appleFeatures, label: "Apple features", icon: .apple),
        Item(section: .protection, label: "Protection", icon: .shieldCheck),
        Item(section: .appUpdates, label: "App updates", icon: .refresh),
        Item(section: .orphans, label: "Leftovers", icon: .file)
    ]

    static let settingsItem = Item(section: .settings, label: "Settings", icon: .settings)

    /// Keyboard up/down order.
    static var orderedSections: [AppSection] {
        (primaryItems + cleanupItems + toolItems + [settingsItem]).map(\.section)
    }

    let selection: AppSection?
    @ObservedObject var scheduler: SchedulerService
    let select: (AppSection) -> Void
    let badge: (Item) -> String?
    var focusedSection: FocusState<AppSection?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Self.primaryItems) { row($0) }
                    groupLabel("Cleanup")
                    ForEach(Self.cleanupItems) { row($0) }
                    groupLabel("Tools")
                    ForEach(Self.toolItems) { row($0) }
                }
            }
            Spacer(minLength: 12)
            scheduleCard
            row(Self.settingsItem, shortcut: "⌘,")
                .padding(.top, 6)
        }
        .padding(14)
        .frame(width: SiftSpacing.railWidth)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: SiftRadius.card, style: .continuous).fill(SiftColor.rail))
        .overlay(RoundedRectangle(cornerRadius: SiftRadius.card, style: .continuous).strokeBorder(SiftColor.stroke, lineWidth: 1))
    }

    /// Leaves room for the traffic lights above the wordmark.
    private var wordmark: some View {
        HStack(spacing: 10) {
            Text(verbatim: "S")
                .font(.siftDisplay(16, weight: 700))
                .foregroundStyle(SiftColor.onAccent)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SiftColor.accent))
            Text(verbatim: "SIFT")
                .font(.siftDisplay(17))
                .tracking(2.4)
                .foregroundStyle(SiftColor.textPrimary)
        }
        .padding(.horizontal, 6)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Sift"))
    }

    private func groupLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .siftStyle(.caption)
            .padding(.horizontal, 10)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func row(_ item: Item, shortcut: String? = nil) -> some View {
        let isSelected: Bool = {
            if selection == item.section { return true }
            if case .cleaning(let category)? = selection { return item.categories.contains(category) }
            return false
        }()
        return Button {
            select(item.section)
        } label: {
            RailRow(item: item, badge: badge(item), shortcut: shortcut, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .focused(focusedSection, equals: item.section)
        .accessibilityLabel(Text(item.label))
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: item.section))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var scheduleCard: some View {
        HStack(spacing: 8) {
            SiftIcon.calendarClock.image(16)
                .foregroundStyle(SiftColor.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: SiftRadius.tile, style: .continuous).fill(SiftColor.accentTint))
            VStack(alignment: .leading, spacing: 2) {
                Text("Scheduled cleanup")
                    .font(.sift(10.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                scheduleSummary
                    .font(.sift(12.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Toggle(isOn: Binding(
                get: { scheduler.config.isEnabled },
                set: { scheduler.toggleEnabled($0) }
            )) { EmptyView() }
                .toggleStyle(.siftSwitch)
                .labelsHidden()
                .accessibilityLabel(Text("Scheduled cleanup"))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SiftColor.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(SiftColor.stroke, lineWidth: 1))
    }

    private var scheduleSummary: Text {
        let config = scheduler.config
        guard config.isEnabled else { return Text("Off") }
        if config.interval == .weekly {
            return Text("Every \(config.weekdaySymbol())")
        }
        return Text(LocalizedStringKey(config.interval.rawValue))
    }

    static func accessibilityIdentifier(for section: AppSection) -> String {
        switch section {
        case .apps: return "sidebar.uninstaller"
        case .orphans: return "sidebar.leftovers"
        case .spaceExplorer: return "sidebar.spaceExplorer"
        case .duplicates: return "sidebar.duplicates"
        case .similarPhotos: return "sidebar.similarPhotos"
        case .protection: return "sidebar.protection"
        case .performance: return "sidebar.performance"
        case .appleFeatures: return "sidebar.appleFeatures"
        case .settings: return "sidebar.settings"
        case .appUpdates: return "sidebar.appUpdates"
        case .cleaning(let category): return "sidebar.cleaning.\(category.id)"
        }
    }
}

private struct RailRow: View {
    let item: SiftRail.Item
    let badge: String?
    let shortcut: String?
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            item.icon.image(16)
                .foregroundStyle(isSelected ? SiftColor.accent : SiftColor.icon)
                .padding(.trailing, 10)
                .accessibilityHidden(true)
            Text(item.label)
                .font(.sift(13, weight: isSelected ? 500 : 400))
                .foregroundStyle(isSelected || hovering ? SiftColor.textPrimary : SiftColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 6)
            if let badge {
                SiftBadge(badge, highlighted: isSelected)
            } else if let shortcut {
                Text(verbatim: shortcut)
                    .font(.siftMono(10.5))
                    .foregroundStyle(SiftColor.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: SiftRadius.nav, style: .continuous)
                .fill(isSelected ? SiftColor.selected : hovering ? SiftColor.selected.opacity(0.55) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: SiftRadius.nav, style: .continuous))
        .onHover { hovering = $0 }
    }
}
