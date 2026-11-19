import SwiftUI

/// A cleanup screen, built to the design's Installers frame: header, filter
/// toolbar, the item list and a floating selection bar. System junk and
/// Developer caches list every category of their group together. The Trash
/// is read-only here and can only be emptied through Finder.
struct CategoryDetailView: View {
    private struct CleanupSelection: Identifiable {
        let id = UUID()
        let items: [CleanableItem]
    }

    private enum ToolbarMenu: Hashable {
        case preset, size, age, sort
    }

    @EnvironmentObject var appState: AppState
    @ObservedObject private var permission = PermissionCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let category: CleaningCategory

    @State private var filter = CleanupReviewFilter()
    /// Keeps the filtered and sorted rows between reads; see `VisibleItemsCache`.
    @State private var visibleCache = VisibleItemsCache()
    @State private var pendingReview: CleanupSelection?
    @State private var openMenu: ToolbarMenu?
    @State private var confirmEmptyTrash = false
    @State private var rescanTask: Task<Void, Never>?
    /// Bumped when a preset is saved or cleared so the menu re-reads defaults.
    @State private var presetRevision = 0

    private var members: [CleaningCategory] { category.cleanupMembers }
    private var isTrash: Bool { category == .trash }
    private var results: [CategoryResult] { members.compactMap { appState.categoryResults[$0] } }
    private var hasResult: Bool { !results.isEmpty }
    private var allItems: [CleanableItem] { results.flatMap(\.items) }
    private var visibleItems: [CleanableItem] { visibleCache.items(for: allItems, filter: filter) }
    private var selectedItems: [CleanableItem] {
        isTrash ? [] : filter.ordered(allItems.filter(appState.isItemSelected))
    }
    private var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    private var isScanning: Bool {
        if case .scanning = appState.scanState { return true }
        return false
    }
    private var presetKey: String { category.cleanupLead.rawValue }

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            header
            if isScanning {
                scanStrip
            }
            if hasResult, !allItems.isEmpty {
                toolbar
                    .padding(.top, 30)
                    .padding(.bottom, 34)
                listCard
                if isTrash {
                    trashBar
                } else {
                    selectionBar
                }
            } else if hasResult || (isTrash && appState.lastScanDate != nil && !isScanning) {
                emptyCard(
                    icon: isTrash ? .trash : .check,
                    title: isTrash && appState.hasFullDiskAccess ? Text("The Trash is empty") : Text("No files found"),
                    description: !appState.hasFullDiskAccess
                        ? Text("Some protected locations are unavailable. Full Disk Access allows a more complete scan.")
                        : isTrash
                            ? Text("Files you move to the Trash show up here.")
                            : Text("There are no cleanup items in this category.")
                ) {
                    if !appState.hasFullDiskAccess {
                        Button("Set up") { requestAccessAndRescan() }
                            .buttonStyle(.siftPrimary)
                    }
                }
            } else if !appState.scanState.isActive {
                emptyCard(
                    icon: category.siftIcon,
                    title: Text("See what is taking up space"),
                    description: Text("Scan first, then review the exact files before removing anything.")
                ) {
                    Button("Scan this category") { rescan() }
                        .buttonStyle(.siftPrimary)
                }
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .siftMenuHost(open: $openMenu) { menuPanel($0) }
        .animation(reduceMotion ? nil : SiftMotion.quick, value: openMenu)
        .navigationTitle(Text(category.cleanupTitle))
        .onAppear(perform: applySavedPresetIfUntouched)
        .onDisappear { rescanTask?.cancel() }
        .sheet(item: $pendingReview) { selection in
            SiftRemovalReview(
                items: selection.items,
                disabled: appState.scanState.isActive,
                cancel: { pendingReview = nil },
                remove: {
                    pendingReview = nil
                    remove(selection.items)
                }
            )
            .siftPresentedLayout()
        }
        .confirmationDialog(
            Text("Empty the Trash?"),
            isPresented: $confirmEmptyTrash,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                Task { await appState.emptyTrash() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Finder will permanently delete \(allItems.count) items (\(SiftFormat.bytes(allItems.reduce(0) { $0 + $1.size }))). This can't be undone.")
        }
        .onChange(of: category) { _ in
            filter = CleanupReviewFilter()
            pendingReview = nil
            openMenu = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    Group {
                        if let date = appState.lastScanDate, hasResult {
                            Text("Cleanup, scanned \(SiftFormat.relativeShort(date, to: timeline.date))")
                        } else {
                            Text("Cleanup, not scanned yet")
                        }
                    }
                    .siftStyle(.label)
                }
                Text(category.cleanupTitle)
                    .siftStyle(.pageTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(category.cleanupDescription)
                    .font(.sift(13))
                    .foregroundStyle(SiftColor.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 16)
            Button {
                rescan()
            } label: {
                Label {
                    hasResult ? Text("Rescan") : Text("Scan")
                } icon: {
                    SiftIcon.rotateCw.image(15).foregroundStyle(SiftColor.textSecondary)
                }
            }
            .buttonStyle(.siftSecondary)
            .disabled(appState.scanState.isActive || appState.isEmptyingTrash)
        }
        .padding(.top, 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var scanStrip: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Scanning \(Text(LocalizedStringKey(appState.currentScanCategory)))…")
                .siftStyle(.label)
                .lineLimit(1)
            SiftMeterBar(fraction: appState.scanProgress)
                .frame(maxWidth: 240)
            Spacer(minLength: 8)
            Button("Stop scan") {
                rescanTask?.cancel()
                appState.cancelScan()
            }
            .buttonStyle(.sift(.secondary, compact: true))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .siftSurface(.card, padding: 0)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            SiftSearchField(text: $filter.query, prompt: Text("Filter by name or path"))
                .frame(minWidth: 180, maxWidth: 340)
            if !isTrash {
                presetPill
                pill(.size, label: Text(LocalizedStringKey(filter.size.rawValue)))
                pill(.age, label: Text(LocalizedStringKey(filter.age.rawValue)))
            }
            pill(.sort, icon: .arrowDownWideNarrow, label: Text(LocalizedStringKey(filter.order.rawValue)))
            Spacer(minLength: 8)
            countSummary
                .font(.siftMono(11.5))
                .foregroundStyle(SiftColor.textTertiary)
                .lineLimit(1)
                .layoutPriority(-1)
        }
        .disabled(appState.scanState.isActive)
    }

    private var countSummary: Text {
        let visible = visibleItems
        let size = SiftFormat.bytes(visible.reduce(0) { $0 + $1.size })
        if visible.count == allItems.count {
            return Text("\(visible.count) items, \(size)")
        }
        return Text("\(visible.count) of \(allItems.count) items, \(size)")
    }

    private var activePreset: CleanupFilterPreset? {
        _ = presetRevision
        if let builtIn = CleanupFilterPreset.builtIns.first(where: { $0.filter == filter }) { return builtIn }
        if let saved = CleanupFilterPreset.savedPreset(forCategory: presetKey), saved.filter == filter,
           filter != CleanupReviewFilter() {
            return saved
        }
        return nil
    }

    private var presetPill: some View {
        let active = activePreset
        return Button {
            toggle(.preset)
        } label: {
            HStack(spacing: 8) {
                SiftIcon.slidersHorizontal.image(15)
                    .foregroundStyle(active == nil ? SiftColor.textSecondary : SiftColor.accent)
                if let active {
                    Text(verbatim: active.name)
                    Text("Preset")
                        .font(.sift(10.5, weight: 500))
                        .foregroundStyle(SiftColor.accent)
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(Capsule(style: .continuous).fill(SiftColor.accentTint))
                } else {
                    Text("Presets")
                }
                SiftIcon.chevronDown.image(14).foregroundStyle(SiftColor.textTertiary)
            }
        }
        .buttonStyle(SiftPillStyle(active: active != nil))
        .siftMenuAnchor(ToolbarMenu.preset)
        .help("Apply a filter preset")
        .accessibilityIdentifier("category.filtersPreset")
    }

    private func pill(_ menu: ToolbarMenu, icon: SiftIcon? = nil, label: Text) -> some View {
        Button {
            toggle(menu)
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    icon.image(15).foregroundStyle(SiftColor.textSecondary)
                }
                label.lineLimit(1)
                SiftIcon.chevronDown.image(14).foregroundStyle(SiftColor.textTertiary)
            }
        }
        .buttonStyle(SiftPillStyle())
        .siftMenuAnchor(menu)
    }

    private func toggle(_ menu: ToolbarMenu) {
        openMenu = openMenu == menu ? nil : menu
    }

    @ViewBuilder
    private func menuPanel(_ menu: ToolbarMenu) -> some View {
        SiftMenuPanel {
            switch menu {
            case .preset:
                presetMenu
            case .size:
                SiftMenuHeader(Text("Size"))
                ForEach(CleanupSizeFilter.allCases) { size in
                    SiftMenuRow(
                        title: Text(LocalizedStringKey(size.rawValue)),
                        detail: itemCountLabel(matching { $0.size = size }),
                        checked: filter.size == size
                    ) {
                        filter.size = size
                        openMenu = nil
                    }
                }
            case .age:
                SiftMenuHeader(Text("Modified"))
                ForEach(CleanupAgeFilter.allCases) { age in
                    SiftMenuRow(
                        title: Text(LocalizedStringKey(age.rawValue)),
                        detail: itemCountLabel(matching { $0.age = age }),
                        checked: filter.age == age
                    ) {
                        filter.age = age
                        openMenu = nil
                    }
                }
            case .sort:
                SiftMenuHeader(Text("Sort"))
                ForEach(CleanupSortOrder.allCases) { order in
                    SiftMenuRow(
                        title: Text(LocalizedStringKey(order.rawValue)),
                        checked: filter.order == order
                    ) {
                        filter.order = order
                        openMenu = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var presetMenu: some View {
        let _ = presetRevision
        let saved = CleanupFilterPreset.savedPreset(forCategory: presetKey)
        SiftMenuHeader(Text("Filter presets"))
        ForEach(CleanupFilterPreset.builtIns) { preset in
            presetRow(preset)
        }
        if let saved, !CleanupFilterPreset.builtIns.contains(where: { $0.filter == saved.filter }) {
            presetRow(saved)
        }
        SiftMenuDivider()
            .padding(.vertical, 2)
        SiftMenuRow(title: Text("Save current filters"), icon: .bookmarkPlus) {
            CleanupFilterPreset.savePreset(
                CleanupFilterPreset(name: String(localized: "Saved"), filter: filter),
                forCategory: presetKey
            )
            presetRevision += 1
            openMenu = nil
        }
        SiftMenuRow(title: Text("Clear saved preset"), icon: .x, muted: true) {
            CleanupFilterPreset.clearSavedPreset(forCategory: presetKey)
            presetRevision += 1
            openMenu = nil
        }
        .disabled(saved == nil)
    }

    private func presetRow(_ preset: CleanupFilterPreset) -> some View {
        SiftMenuRow(
            title: Text(verbatim: preset.name),
            detail: itemCountLabel(preset.filter.apply(to: allItems).count),
            checked: filter == preset.filter
        ) {
            filter = preset.filter
            openMenu = nil
        }
    }

    /// How many items the current filter would show with `change` applied.
    private func matching(_ change: (inout CleanupReviewFilter) -> Void) -> Int {
        var candidate = filter
        change(&candidate)
        return candidate.apply(to: allItems).count
    }

    private func itemCountLabel(_ count: Int) -> String {
        String(localized: "\(count) items")
    }

    /// A preset saved for this category applies once, when the view first
    /// appears — never on top of filters the user is already adjusting.
    private func applySavedPresetIfUntouched() {
        guard filter == CleanupReviewFilter(),
              let saved = CleanupFilterPreset.savedPreset(forCategory: presetKey)
        else { return }
        filter = saved.filter
    }

    // MARK: - List

    private var listCard: some View {
        VStack(spacing: 2) {
            columnHeader
            if visibleItems.isEmpty {
                VStack(spacing: 10) {
                    Text("No matching files").siftStyle(.cardTitle)
                    Text("Try another name, size, or date range.").siftStyle(.label)
                    Button("Clear filters") { filter = CleanupReviewFilter() }
                        .buttonStyle(.sift(.secondary, compact: true))
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleItems) { item in
                            CleanupFileRow(item: item, showsCategory: category.isCleanupGroup, selectable: !isTrash)
                        }
                    }
                }
                .disabled(appState.scanState.isActive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .siftSurface(.card, padding: 10)
    }

    private var columnHeader: some View {
        HStack(spacing: 14) {
            if !isTrash { Color.clear.frame(width: 20) }
            Color.clear.frame(width: 36)
            columnTitle(Text("Name"), sorted: filter.order == .name ? true : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            columnTitle(Text("Modified"), sorted: [.newest, .oldest].contains(filter.order) ? filter.order == .newest : nil)
                .frame(width: 130, alignment: .leading)
            columnTitle(Text("Size"), sorted: [.largest, .smallest].contains(filter.order) ? filter.order == .largest : nil)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    /// `sorted`: nil when the list is not sorted by this column, true when
    /// descending (arrow down), false when ascending.
    private func columnTitle(_ title: Text, sorted: Bool?) -> some View {
        HStack(spacing: 4) {
            title.font(.sift(11.5))
            if let descending = sorted {
                SiftIcon.arrowDown.image(12)
                    .rotationEffect(.degrees(descending ? 0 : 180))
            }
        }
        .foregroundStyle(sorted == nil ? SiftColor.textTertiary : SiftColor.textSecondary)
    }

    // MARK: - Selection bar

    private var selectionBar: some View {
        let visible = visibleItems
        let visibleIDs = Set(visible.map(\.id))
        let selected = selectedItems
        let hiddenCount = selected.filter { !visibleIDs.contains($0.id) }.count
        let allVisibleSelected = !visible.isEmpty && visible.allSatisfy(appState.isItemSelected)
        let confirms = appState.confirmBeforeDelete
        return HStack(spacing: 14) {
            Text(verbatim: "\(selected.count)")
                .font(.sift(12, weight: 700))
                .foregroundStyle(selected.isEmpty ? SiftColor.textTertiary : SiftColor.onAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, SelectionBadgeRule.horizontalPadding(for: selected.count))
                .frame(minWidth: SelectionBadgeRule.minimumSize, minHeight: SelectionBadgeRule.minimumSize)
                .background(Capsule().fill(selected.isEmpty ? SiftColor.track : SiftColor.accent))
            Text("selected")
                .font(.sift(13.5, weight: 500))
                .foregroundStyle(SiftColor.textPrimary)
            Text(verbatim: SiftFormat.bytes(selectedSize))
                .font(.siftMono(12.5))
                .foregroundStyle(SiftColor.accent)
            Group {
                if hiddenCount > 0 {
                    Text("Includes \(hiddenCount) selected items hidden by filters.")
                } else {
                    Text("Cleanup permanently removes files unless marked Move to Trash.")
                }
            }
            .font(.sift(12))
            .foregroundStyle(SiftColor.textTertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                appState.setSelection(!allVisibleSelected, for: visible)
            } label: {
                (allVisibleSelected ? Text("Deselect all") : Text("Select all \(visible.count)"))
                    .foregroundColor(SiftColor.textSecondary)
            }
            .buttonStyle(.sift(.quiet))
            .disabled(visible.isEmpty || appState.scanState.isActive)
            Button {
                if confirms {
                    pendingReview = CleanupSelection(items: selected)
                } else {
                    remove(selected)
                }
            } label: {
                HStack(spacing: 10) {
                    SiftIcon.trash2.image(15)
                    Text("Review and remove").font(.sift(13))
                    if confirms { SiftKeyHint("⏎", onAccent: true) }
                }
            }
            .buttonStyle(.siftPrimary)
            // Return would otherwise remove straight from the search field.
            .keyboardShortcut(confirms ? .defaultAction : nil)
            .disabled(selected.isEmpty || appState.scanState.isActive)
            .accessibilityIdentifier("category.reviewRemoval")
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(height: 64)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.07), radius: 16, y: 12)
    }

    private func remove(_ items: [CleanableItem]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty, !isTrash else { return }
        if category.isCleanupGroup {
            appState.cleanAll(itemIDs: ids)
        } else {
            appState.cleanCategory(category, itemIDs: ids)
        }
    }

    // MARK: - Trash

    private var trashBar: some View {
        let size = allItems.reduce(Int64(0)) { $0 + $1.size }
        return HStack(spacing: 14) {
            SiftIcon.trash.image(14)
                .foregroundStyle(SiftColor.textSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(SiftColor.track))
            Text("\(allItems.count) items in the Trash")
                .font(.sift(13.5, weight: 500))
                .foregroundStyle(SiftColor.textPrimary)
            Text(verbatim: SiftFormat.bytes(size))
                .font(.siftMono(12.5))
                .foregroundStyle(SiftColor.accent)
            Text("Finder empties the Trash. This can't be undone.")
                .font(.sift(12))
                .foregroundStyle(SiftColor.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if appState.isEmptyingTrash {
                ProgressView().controlSize(.small)
                Text("Emptying the Trash…").siftStyle(.label)
            }
            Button {
                confirmEmptyTrash = true
            } label: {
                HStack(spacing: 10) {
                    SiftIcon.trash.image(15)
                    Text("Empty Trash").font(.sift(13))
                }
            }
            .buttonStyle(.siftPrimary)
            .disabled(allItems.isEmpty || appState.isEmptyingTrash || appState.scanState.isActive)
            .accessibilityIdentifier("category.emptyTrash")
        }
        .padding(.leading, 22)
        .padding(.trailing, 12)
        .frame(height: 64)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.07), radius: 16, y: 12)
    }

    // MARK: - Empty states

    private func emptyCard<Actions: View>(
        icon: SiftIcon,
        title: Text,
        description: Text,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(spacing: 12) {
            SiftIconTile(icon: icon, size: 48)
            title.siftStyle(.metricSmall)
            description
                .siftStyle(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            actions().padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .siftSurface(.card)
    }

    // MARK: - Scanning

    /// Scans every category this screen lists. Groups scan one member after
    /// another, since AppState runs one category scan at a time.
    private func rescan() {
        let targets = members.filter(CleaningCategory.smartScanCategories.contains)
        guard let first = targets.first, !appState.scanState.isActive else { return }
        rescanTask?.cancel()
        appState.scanSingleCategory(first)
        guard targets.count > 1 else { return }
        rescanTask = Task { @MainActor in
            for next in targets.dropFirst() {
                while appState.scanState.isActive {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if Task.isCancelled { return }
                }
                guard !Task.isCancelled, !appState.scanWasCancelled else { return }
                appState.scanSingleCategory(next)
            }
        }
    }

    private func requestAccessAndRescan() {
        permission.requestAccess(context: .general) {
            appState.checkFullDiskAccess()
            rescan()
        }
    }
}

// MARK: - Visible rows

/// Answers "which rows are visible" for one set of inputs.
///
/// The list, both toolbar counters and the selection bar all read the visible
/// rows, so one body evaluation used to filter and sort every row four times.
/// A clean publishes progress dozens of times per second, which kept the sort
/// of thousands of rows on the main thread for most of the pass and froze the
/// window. The cache keeps the previous result until the items, the filter or
/// the search text actually change.
final class VisibleItemsCache {
    private struct Inputs: Equatable {
        let filter: CleanupReviewFilter
        let items: [CleanableItem]
    }

    private var inputs: Inputs?
    private var output: [CleanableItem] = []
    /// Number of times the filter really ran. Read by the tests that pin the
    /// "once per input set" contract.
    private(set) var recomputations = 0

    func items(for items: [CleanableItem], filter: CleanupReviewFilter) -> [CleanableItem] {
        let candidate = Inputs(filter: filter, items: items)
        if candidate == inputs { return output }
        let computed = filter.apply(to: items)
        inputs = candidate
        output = computed
        recomputations += 1
        return computed
    }
}

/// Width rule for the selected-count badge.
///
/// One and two digits sit in a 28 pt circle. From three digits the text needs
/// more room than the circle gives and wrapped into a tall oval, so the badge
/// widens into a capsule that keeps the count on one line.
enum SelectionBadgeRule {
    static let minimumSize: CGFloat = 28

    static func horizontalPadding(for count: Int) -> CGFloat {
        count > 99 ? 8 : 0
    }
}

// MARK: - Row

private struct CleanupFileRow: View {
    @EnvironmentObject var appState: AppState
    let item: CleanableItem
    let showsCategory: Bool
    let selectable: Bool
    @State private var hovering = false

    var body: some View {
        let selected = selectable && appState.isItemSelected(item)
        HStack(spacing: 14) {
            if selectable {
                Toggle(isOn: appState.itemBinding(for: item)) { EmptyView() }
                    .toggleStyle(.siftCheckbox)
                    .labelsHidden()
                    .accessibilityLabel("Select \(item.name)")
                    .help(item.isSelected ? Text(verbatim: "") : Text("Personal data or an optional cleanup action. Left unselected by default."))
            }
            SiftIconTile(icon: Self.icon(for: item), tone: selected ? .accent : .neutral, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.sift(13.5, weight: 500))
                        .foregroundStyle(SiftColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if showsCategory {
                        Text(item.category.cleanupTitle)
                            .font(.sift(10.5, weight: 500))
                            .foregroundStyle(SiftColor.textTertiary)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Capsule(style: .continuous).fill(SiftColor.badge))
                            .fixedSize()
                    }
                }
                Text(item.isActionItem
                     ? String(localized: "Managed cleanup action")
                     : (item.note ?? (item.path as NSString).abbreviatingWithTildeInPath))
                    .font(.siftMono(10.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hovering && !item.isActionItem {
                Button { reveal() } label: {
                    HStack(spacing: 6) {
                        SiftIcon.folderOpen.image(13)
                        Text("Show in Finder")
                    }
                    .font(.sift(11.5))
                    .foregroundStyle(SiftColor.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule(style: .continuous).fill(SiftColor.track))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reveal \(item.name) in Finder")
            }
            Group {
                if let date = item.lastModified {
                    Text(verbatim: SiftFormat.relative(date))
                } else {
                    Text(verbatim: "–")
                }
            }
            .font(.sift(12))
            .foregroundStyle(SiftColor.textTertiary)
            .lineLimit(1)
            .frame(width: 130, alignment: .leading)
            Text(item.formattedSize)
                .font(.siftMono(12.5))
                .foregroundStyle(selected ? SiftColor.accent : SiftColor.textPrimary)
                .lineLimit(1)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .siftRowBackground(accented: selected, radius: 16)
        .onHover { hovering = $0 }
        .accessibilityAction(named: Text("Reveal in Finder")) { if !item.isActionItem { reveal() } }
        .contextMenu {
            if !item.isActionItem {
                Button("Reveal in Finder") { reveal() }
                Button("Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.path, forType: .string)
                }
                if selectable {
                    Divider()
                    Button("Always exclude from cleanup") { appState.excludeFromCleanup(item) }
                        .disabled(appState.scanState.isActive)
                }
            }
        }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    static func icon(for item: CleanableItem) -> SiftIcon {
        if item.isActionItem { return .settings }
        switch (item.path as NSString).pathExtension.lowercased() {
        case "dmg", "iso", "img": return .disc3
        case "pkg", "mpkg": return .package
        case "zip", "xip", "gz", "tgz", "tar", "rar", "7z": return .fileArchive
        case "eml", "emlx", "mbox": return .mail
        default: break
        }
        if item.category == .mailAttachments { return .mail }
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: item.path, isDirectory: &directory), directory.boolValue {
            return .folder
        }
        return .file
    }
}
