import SwiftUI

/// Overview: the Sift dashboard. A hero with the disk meter, where the junk
/// sits, the biggest single items, and the battery, startup and history cards.
struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var permission = PermissionCoordinator.shared
    var onNavigate: (AppSection) -> Void = { _ in }

    @State private var reviewItems: [CleanableItem]?
    @State private var battery: BatteryStatus?
    @State private var startupItems: [PerformanceStartupItem]?
    @State private var startupFailed = false

    var body: some View {
        // Always scrollable: ViewThatFits accepted `content` here even when the
        // fixed-width side column overflowed the window, clipping the hero's
        // top edge and the bottom cards.
        ScrollView(.vertical, showsIndicators: false) { content }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await loadSystemCards() }
        .sheet(isPresented: Binding(
            get: { reviewItems != nil },
            set: { if !$0 { reviewItems = nil } }
        )) {
            SiftRemovalReview(
                items: reviewItems ?? [],
                disabled: appState.scanState.isActive,
                cancel: { reviewItems = nil },
                remove: {
                    let ids = Set((reviewItems ?? []).map(\.id))
                    reviewItems = nil
                    appState.cleanAll(itemIDs: ids)
                }
            )
        }
    }

    private var content: some View {
        VStack(spacing: SiftSpacing.gutter) {
            DashboardHero(
                onNavigate: onNavigate,
                review: { reviewItems = selectedItems },
                requestAccess: requestAccess
            )
            HStack(alignment: .top, spacing: SiftSpacing.gutter) {
                VStack(spacing: SiftSpacing.gutter) {
                    WhereItSitsCard(onNavigate: onNavigate)
                    BiggestWinsCard(onNavigate: onNavigate)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(spacing: SiftSpacing.gutter) {
                    if let battery, battery.isInstalled {
                        BatteryCard(status: battery)
                    }
                    StartupItemsCard(items: startupItems, failed: startupFailed)
                    ReclaimedCard()
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .frame(width: 392)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var selectedItems: [CleanableItem] {
        // The dashboard shows no sort control, so the sheet reads largest first.
        CleanupReviewFilter(order: .largest)
            .ordered(appState.allResults.flatMap(\.items).filter(appState.isItemSelected))
    }

    private func requestAccess() {
        permission.requestAccess(context: .general) {
            appState.checkFullDiskAccess()
        }
    }

    /// Battery and launchd reads shell out, so they run off the main actor.
    private func loadSystemCards() async {
        async let batteryStatus = BatteryInspector().inspect()
        async let inspection = Task.detached(priority: .utility) {
            try await PerformanceInspector().inspect()
        }.result
        let (status, startup) = await (batteryStatus, inspection)
        guard !Task.isCancelled else { return }
        battery = status
        switch startup {
        case .success(let value):
            startupItems = value.startupItems
        case .failure:
            startupFailed = true
        }
    }
}

// MARK: - Hero

private struct DashboardHero: View {
    @EnvironmentObject var appState: AppState
    let onNavigate: (AppSection) -> Void
    let review: () -> Void
    let requestAccess: () -> Void

    private var hasResults: Bool { !appState.categoryResults.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: eyebrow)
                        .siftStyle(.label)
                        .lineLimit(1)
                    headline
                        .siftStyle(.hero)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 10) {
                    statusLine
                    HStack(spacing: 8) { actions }
                }
            }
            DiskMeter(
                info: appState.diskInfo,
                reclaimable: hasResults ? appState.totalJunkSize : nil
            )
            footer
        }
        .siftSurface(.hero)
    }

    // MARK: Copy

    private var eyebrow: String {
        let total = appState.diskInfo.totalSpace > 0
            ? String(format: String(localized: "%@ total"), SiftFormat.bytes(appState.diskInfo.totalSpace))
            : nil
        return [SystemInfo.modelName, SystemInfo.macOSVersion, total].compactMap { $0 }.joined(separator: ", ")
    }

    private var headline: Text {
        switch appState.scanState {
        case .scanning:
            return Text("Scanning your Mac")
        case .cleaning:
            return Text("Cleaning selected items")
        case .cleaned:
            if appState.lastCleanupHadFailures { return Text("Some items need attention") }
            return Text("\(SiftFormat.bytes(appState.totalFreedSpace)) removed")
        case .idle, .completed:
            guard hasResults else {
                return Text("\(SiftFormat.bytes(appState.diskInfo.freeSpace)) free")
            }
            guard appState.totalJunkSize > 0 else { return Text("Nothing to clean") }
            return Text("\(SiftFormat.bytes(appState.totalJunkSize)) is junk")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 10) {
            if !appState.hasFullDiskAccess {
                Button(action: requestAccess) {
                    SiftStatusPill(Text("Limited access"), tone: .warning)
                }
                .buttonStyle(.plain)
                .help("Full Disk Access is off. Protected caches and app containers will be skipped.")
            }
            switch appState.scanState {
            case .scanning:
                statusText(Text(appState.scanProgress, format: .percent.precision(.fractionLength(0))), tone: .accent)
            case .cleaning:
                statusText(Text(appState.cleanProgress, format: .percent.precision(.fractionLength(0))), tone: .accent)
            case .cleaned:
                statusText(
                    appState.lastCleanupHadFailures ? Text("needs attention") : Text("cleanup complete"),
                    tone: appState.lastCleanupHadFailures ? .warning : .success
                )
            case .idle, .completed:
                if let date = appState.lastScanDate, hasResults {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        statusText(
                            appState.scanWasCancelled
                                ? Text("scan stopped \(SiftFormat.relativeShort(date, to: timeline.date))")
                                : Text("scanned \(SiftFormat.relativeShort(date, to: timeline.date))"),
                            tone: appState.scanWasCancelled ? .warning : .success
                        )
                    }
                } else {
                    statusText(Text("not scanned yet"), tone: .neutral)
                }
            }
        }
    }

    private func statusText(_ text: Text, tone: SiftTone) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone == .neutral ? SiftColor.faint : tone.foreground)
                .frame(width: 6, height: 6)
            text.siftStyle(.mono)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch appState.scanState {
        case .scanning:
            Button("Stop scan") { appState.cancelScan() }
                .buttonStyle(.siftSecondary)
        case .cleaning:
            EmptyView()
        case .cleaned:
            Button("Done") { appState.scanState = .idle }
                .buttonStyle(.siftSecondary)
            scanButton(Text("Scan again"))
        case .idle, .completed:
            Button {
                if hasResults, appState.totalSelectedSize > 0 {
                    review()
                } else {
                    onNavigate(.spaceExplorer)
                }
            } label: {
                Label { Text("See what's inside") } icon: { SiftIcon.scanSearch.image(15) }
            }
            .buttonStyle(.siftSecondary)
            .help(hasResults && appState.totalSelectedSize > 0
                  ? Text("Review the selected items before removing them")
                  : Text("Browse folders by size"))
            .accessibilityIdentifier("dashboard.review")
            scanButton(hasResults ? Text("Scan again") : Text("Scan this Mac"))
        }
    }

    private func scanButton(_ title: Text) -> some View {
        Button {
            appState.startSmartScan()
        } label: {
            HStack(spacing: 8) {
                SiftIcon.rotateCw.image(15)
                title
                SiftKeyHint("⌘R", onAccent: true)
            }
        }
        .buttonStyle(.siftPrimary)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(appState.scanState.isActive)
        .accessibilityIdentifier("dashboard.scan")
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        switch appState.scanState {
        case .scanning:
            progressFooter(
                progress: appState.scanProgress,
                label: Text(LocalizedStringKey(appState.currentScanCategory)),
                note: Text("Stopping keeps the results found so far.")
            ) {
                ScanPathTicker(ticker: appState.scanTicker)
            }
        case .cleaning:
            progressFooter(
                progress: appState.cleanProgress,
                label: Text("Removing the items you selected."),
                note: Text("Keep Sift open until cleanup finishes.")
            ) { EmptyView() }
        case .cleaned where appState.cleanError != nil:
            Text(appState.cleanError ?? "")
                .siftStyle(.body)
                .lineLimit(3)
                .frame(height: 28, alignment: .leading)
        default:
            chips
        }
    }

    private func progressFooter<Detail: View>(
        progress: Double,
        label: Text,
        note: Text,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SiftMeterBar(fraction: progress)
            HStack(spacing: 12) {
                label.siftStyle(.label).lineLimit(1).fixedSize()
                detail()
                Spacer(minLength: 8)
                note.siftStyle(.caption).lineLimit(1)
            }
        }
        .frame(minHeight: 28)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            if appState.diskInfo.purgeableSpace > 0 {
                SiftChip(Text("Purgeable by macOS"), value: SiftFormat.bytes(appState.diskInfo.purgeableSpace))
            }
            if let containers = appState.containersSize {
                SiftChip(Text("Containers"), value: SiftFormat.bytes(containers))
            }
            if let caches = appState.cachesSize {
                SiftChip(Text("Caches"), value: SiftFormat.bytes(caches))
            }
            if let trash = appState.categoryResults[.trash]?.totalSize {
                SiftChip(Text("Trash"), value: SiftFormat.bytes(trash))
            } else if hasResults {
                SiftChip(Text("Trash"), value: SiftFormat.bytes(0))
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
    }
}

/// Reclaimable, in use and free as three proportional capsules.
private struct DiskMeter: View {
    let info: DiskInfo
    /// nil before a scan: the meter then shows only in use and free.
    let reclaimable: Int64?

    var body: some View {
        GeometryReader { proxy in
            let widths = segmentWidths(total: proxy.size.width - 8)
            HStack(spacing: 4) {
                if let reclaimable, let width = widths.reclaimable {
                    HStack {
                        Text("Reclaimable")
                            .font(.sift(11, weight: 500))
                            .foregroundStyle(SiftColor.onAccentMuted)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(verbatim: SiftFormat.bytes(reclaimable))
                            .font(.siftDisplay(16))
                            .foregroundStyle(SiftColor.onAccent)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(Capsule(style: .continuous).fill(SiftColor.accent))
                }
                Text("\(SiftFormat.bytes(inUse)) in use")
                    .font(.siftDisplay(16, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(Capsule(style: .continuous).fill(SiftColor.meterUsed))
                Text("\(SiftFormat.bytes(info.freeSpace)) free")
                    .font(.siftDisplay(16, weight: 500))
                    .foregroundStyle(SiftColor.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .frame(width: widths.free, alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .background(Capsule(style: .continuous).fill(SiftColor.meterFree))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(SiftColor.controlStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    )
            }
            .padding(4)
        }
        .frame(height: 56)
        .background(Capsule(style: .continuous).fill(SiftColor.window))
        .accessibilityElement(children: .combine)
    }

    private var used: Int64 { max(0, info.totalSpace - info.freeSpace) }
    private var inUse: Int64 { max(0, used - (reclaimable ?? 0)) }

    /// Proportional widths with a floor so each label stays readable.
    private func segmentWidths(total: CGFloat) -> (reclaimable: CGFloat?, free: CGFloat) {
        let disk = Double(max(info.totalSpace, 1))
        let available = max(total - (reclaimable == nil ? 4 : 8), 0)
        let free = min(max(available * CGFloat(Double(info.freeSpace) / disk), 140), available * 0.4)
        guard let reclaimable else { return (nil, free) }
        let junk = min(max(available * CGFloat(Double(reclaimable) / disk), 170), available * 0.4)
        return (junk, free)
    }
}

private struct ScanPathTicker: View {
    @ObservedObject var ticker: ScanProgressTicker

    var body: some View {
        Text(ticker.path.isEmpty ? String(localized: "Preparing the next area…") : ticker.path)
            .font(.siftMono(10.5))
            .foregroundStyle(SiftColor.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
            .accessibilityLabel("Current scan path")
            .accessibilityValue(ticker.path)
    }
}

// MARK: - Where it sits

struct WhereItSitsCard: View {
    @EnvironmentObject var appState: AppState
    let onNavigate: (AppSection) -> Void

    struct Row: Identifiable {
        let item: SiftRail.Item
        let size: Int64
        let count: Int
        let measured: Bool
        var id: AppSection { item.section }
    }

    private var rows: [Row] {
        SiftRail.cleanupItems.map { item in
            let results = item.categories.compactMap { appState.categoryResults[$0] }
            return Row(
                item: item,
                size: results.reduce(0) { $0 + $1.totalSize },
                count: results.reduce(0) { $0 + $1.itemCount },
                measured: !results.isEmpty
            )
        }
    }

    var body: some View {
        let rows = self.rows
        let largest = rows.max { $0.size < $1.size }
        let maxSize = max(largest?.size ?? 0, 1)
        let leadRow = (largest?.size ?? 0) > 0 ? largest : nil
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Where it sits")) {
                if rows.contains(where: \.measured) {
                    Text("\(rows.reduce(0) { $0 + $1.count }) items")
                        .siftStyle(.mono)
                }
            }
            VStack(spacing: 2) {
                ForEach(rows) { row in
                    WhereRow(
                        row: row,
                        fraction: Double(row.size) / Double(maxSize),
                        isLargest: row.id == leadRow?.id
                    ) { onNavigate(row.item.section) }
                }
            }
            HStack(spacing: 8) {
                SiftFootnote(Text("Nothing is deleted without review"), icon: .shieldCheck)
                Spacer(minLength: 8)
                let target = leadRow ?? rows[0]
                Button(Self.openLabel(for: target.item.section)) { onNavigate(target.item.section) }
                    .buttonStyle(.siftSecondary)
            }
            .padding(.top, 2)
        }
        .siftSurface(.card)
    }

    static func openLabel(for section: AppSection) -> LocalizedStringKey {
        switch section {
        case .cleaning(.xcodeJunk): return "Open developer caches"
        case .cleaning(.installers): return "Open installers"
        case .cleaning(.largeFiles): return "Open large & old files"
        case .cleaning(.mailAttachments): return "Open mail files"
        case .cleaning(.trash): return "Open Trash"
        default: return "Open system junk"
        }
    }
}

/// Column widths for the Overview "Where it sits" rows.
///
/// The row is ~372 pt wide at the 1080 pt minimum window width: icon tile 32 +
/// label + meter + size 72 + chevron 16 + spacing and padding leave the meter as
/// the only column that can give way, so it collapsed to a dot and the
/// proportion read as nothing. It keeps `meterMinWidth` instead and the label
/// column truncates, with the full name on hover.
enum WhereRowLayout {
    static let meterMinWidth: CGFloat = 56
    static let meterIdealWidth: CGFloat = 120

    /// Columns that never flex in a Where row: the row's own horizontal
    /// padding, the icon tile, the four 14 pt gaps, the size column and the
    /// chevron.
    static let fixedChrome: CGFloat = 20 + 32 + 14 * 4 + 72 + 16

    /// Width the Overview card's left column gives a Where row at
    /// `windowWidth`: window gutter on both sides, the rail and its gap, the
    /// fixed 392 pt right column and its gap, then the card's own padding.
    static func rowWidth(atWindowWidth windowWidth: CGFloat) -> CGFloat {
        let content = windowWidth - SiftSpacing.gutter * 2 - SiftSpacing.railWidth - SiftSpacing.gutter
        let card = content - rightColumnWidth - SiftSpacing.gutter
        return max(0, card - SiftSpacing.cardPadding * 2)
    }

    static let rightColumnWidth: CGFloat = 392

    /// Width the meter gets out of the `space` left for the label and the
    /// meter together: enough for the meter's ideal width once the label has
    /// its own, shrinking to `meterMinWidth` before the label is clipped.
    static func meterWidth(space: CGFloat, labelIdealWidth: CGFloat) -> CGFloat {
        min(max(space - labelIdealWidth, meterMinWidth), meterIdealWidth)
    }

    /// Width the label gets; whatever the meter leaves. It only falls below
    /// its text width when the row cannot hold the meter's minimum too.
    static func labelWidth(space: CGFloat, labelIdealWidth: CGFloat) -> CGFloat {
        max(0, space - meterWidth(space: space, labelIdealWidth: labelIdealWidth))
    }

    /// Five columns in the order icon, label, meter, size, chevron, spaced by
    /// `spacing`. An HStack cannot express the rule above: with two flexible
    /// columns it splits the leftover space between them, which clipped the
    /// category name while the meter still had slack.
    struct Row: Layout {
        var spacing: CGFloat = 14

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let rowWidth = proposal.width ?? 0
            let widths = columnWidths(rowWidth: rowWidth, subviews: subviews)
            let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return CGSize(width: rowWidth, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let widths = columnWidths(rowWidth: bounds.width, subviews: subviews)
            var x = bounds.minX
            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(ProposedViewSize(width: widths[index], height: nil))
                subview.place(
                    at: CGPoint(x: x, y: bounds.midY - size.height / 2),
                    proposal: ProposedViewSize(width: widths[index], height: nil)
                )
                x += widths[index] + spacing
            }
        }

        /// Icon, size column and chevron keep their size; the label and the
        /// meter share the rest by the rule in `WhereRowLayout`.
        private func columnWidths(rowWidth: CGFloat, subviews: Subviews) -> [CGFloat] {
            guard subviews.count == 5 else {
                return subviews.map { $0.sizeThatFits(.unspecified).width }
            }
            let fixed = subviews[0].sizeThatFits(.unspecified).width
                + subviews[3].sizeThatFits(.unspecified).width
                + subviews[4].sizeThatFits(.unspecified).width
                + spacing * 4
            let space = max(0, rowWidth - fixed)
            let labelIdeal = subviews[1].sizeThatFits(.unspecified).width
            let label = WhereRowLayout.labelWidth(space: space, labelIdealWidth: labelIdeal)
            let meter = WhereRowLayout.meterWidth(space: space, labelIdealWidth: labelIdeal)
            return [
                subviews[0].sizeThatFits(.unspecified).width,
                label,
                meter,
                subviews[3].sizeThatFits(.unspecified).width,
                subviews[4].sizeThatFits(.unspecified).width,
            ]
        }
    }
}

struct WhereRow: View {
    let row: WhereItSitsCard.Row
    let fraction: Double
    let isLargest: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            WhereRowLayout.Row(spacing: 14) {
                SiftIconTile(icon: row.item.icon, tone: isLargest ? .accent : .neutral, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.item.label)
                        .font(.sift(13, weight: 500))
                        .foregroundStyle(SiftColor.textPrimary)
                        .lineLimit(1)
                    Group {
                        if row.measured {
                            Text("\(row.count) items")
                        } else {
                            Text("not scanned")
                        }
                    }
                    .siftStyle(.monoSmall)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(row.item.label)
                SiftMeterBar(fraction: row.measured ? fraction : 0, fill: isLargest ? SiftColor.accent : SiftColor.accentDim)
                Text(verbatim: row.measured ? SiftFormat.bytes(row.size) : "–")
                    .font(.siftDisplay(16, weight: 500))
                    .foregroundStyle(isLargest ? SiftColor.accent : SiftColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 72, alignment: .trailing)
                SiftIcon.chevronRight.image(16)
                    .foregroundStyle(isLargest ? SiftColor.accent : SiftColor.faint)
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .siftRowBackground(selected: isLargest)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(SiftRail.accessibilityIdentifier(for: row.item.section).replacingOccurrences(of: "sidebar.", with: "dashboard.where."))
    }
}

// MARK: - Biggest single wins

private struct BiggestWinsCard: View {
    @EnvironmentObject var appState: AppState
    let onNavigate: (AppSection) -> Void

    var body: some View {
        let items = appState.biggestItems(limit: 3)
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Biggest single wins")) {
                if !items.isEmpty {
                    Text("largest first").siftStyle(.mono)
                }
            }
            if items.isEmpty {
                (appState.categoryResults.isEmpty
                    ? Text("Scan this Mac to list the largest items you can remove.")
                    : Text("No large items to remove."))
                    .siftStyle(.label)
                    .padding(.horizontal, 10)
            } else {
                VStack(spacing: 2) {
                    ForEach(items) { item in
                        WinRow(item: item) { onNavigate(.cleaning(item.category.cleanupLead)) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface(.card)
    }
}

private struct WinRow: View {
    let item: CleanableItem
    let review: () -> Void
    @State private var hovering = false

    private var isDirectory: Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: item.path, isDirectory: &directory) && directory.boolValue
    }

    var body: some View {
        Button(action: review) {
            HStack(spacing: 12) {
                (isDirectory ? SiftIcon.folder : SiftIcon.file).image(15)
                    .foregroundStyle(SiftColor.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.sift(12.5))
                        .foregroundStyle(SiftColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(verbatim: ((item.path as NSString).deletingLastPathComponent as NSString).abbreviatingWithTildeInPath)
                        .siftStyle(.monoSmall)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if hovering {
                    Text("Review")
                        .font(.sift(11.5, weight: 500))
                        .foregroundStyle(SiftColor.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule(style: .continuous).fill(SiftColor.accentTint))
                }
                Text(verbatim: item.formattedSize)
                    .siftStyle(.monoValue)
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .siftRowBackground()
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.path)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the category to review this item"))
    }
}

// MARK: - Battery

private struct BatteryCard: View {
    let status: BatteryStatus

    var body: some View {
        HStack(spacing: 18) {
            SiftRing(fraction: Double(status.healthPercent ?? 0) / 100) {
                Text(verbatim: status.healthPercent.map { "\($0)%" } ?? "–")
                    .font(.siftDisplay(24))
                    .foregroundStyle(SiftColor.textPrimary)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Battery health").siftStyle(.cardTitle)
                    Spacer(minLength: 8)
                    if let pill = statePill { pill }
                }
                if let charge = status.chargePercent {
                    Text("\(charge)% charge")
                        .font(.sift(12.5))
                        .foregroundStyle(SiftColor.textSecondary)
                }
                if let detail {
                    Text(verbatim: detail).siftStyle(.monoSmall).lineLimit(1)
                }
            }
        }
        .siftSurface(.card)
        .accessibilityElement(children: .combine)
    }

    private var statePill: SiftStatusPill? {
        guard let charging = status.isCharging else { return nil }
        if charging, let charge = status.chargePercent, charge >= 100 {
            return SiftStatusPill(Text("Fully charged"), tone: .success)
        }
        return charging
            ? SiftStatusPill(Text("Charging"), tone: .success)
            : SiftStatusPill(Text("On battery"), tone: .neutral)
    }

    /// "215 cycles, 4082 / 4629 mAh"; parts that could not be read are left out.
    private var detail: String? {
        var parts: [String] = []
        if let cycles = status.cycleCount {
            parts.append(String(format: String(localized: "%lld cycles"), Int64(cycles)))
        }
        if let current = status.maxCapacityMAh, let design = status.designCapacityMAh {
            parts.append(String(format: String(localized: "%lld / %lld mAh"), Int64(current), Int64(design)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Startup items

private struct StartupItemsCard: View {
    let items: [PerformanceStartupItem]?
    let failed: Bool

    private var notLoading: Int { (items ?? []).filter { $0.status == .notLoaded }.count }

    /// Items launchd refuses to load come first: they are the ones to look at.
    private var shown: [PerformanceStartupItem] {
        let rank: (PerformanceStartupItem) -> Int = { item in
            switch item.status {
            case .notLoaded: return 0
            case .loaded: return 1
            case nil: return 2
            case .disabled: return 3
            }
        }
        return Array((items ?? []).sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Startup items")) {
                if notLoading > 0 {
                    SiftStatusPill(Text("\(notLoading) not loading"), tone: .warning)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: items.map { "\($0.count)" } ?? "–")
                    .siftStyle(.metricSmall)
                (failed ? Text("couldn't read launch items") : Text("registered with launchd"))
                    .font(.sift(12.5))
                    .foregroundStyle(SiftColor.textSecondary)
            }
            if !shown.isEmpty {
                VStack(spacing: 4) {
                    ForEach(shown) { item in
                        HStack(spacing: 10) {
                            Circle().fill(dotColor(item.status)).frame(width: 7, height: 7)
                            Text(verbatim: item.label)
                                .font(.siftMono(11))
                                .foregroundStyle(SiftColor.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            statusLabel(item.status)
                                .font(.sift(11))
                                .foregroundStyle(item.status == .notLoaded ? SiftColor.warning : SiftColor.textTertiary)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: SiftRadius.tile, style: .continuous).fill(SiftColor.control))
                        .help(item.sourceURL.path)
                    }
                }
            }
        }
        .siftSurface(.card)
    }

    private func dotColor(_ status: PerformanceStartupStatus?) -> Color {
        switch status {
        case .loaded: return SiftColor.success
        case .notLoaded: return SiftColor.warning
        case .disabled, nil: return SiftColor.faint
        }
    }

    private func statusLabel(_ status: PerformanceStartupStatus?) -> Text {
        switch status {
        case .loaded: return Text("loaded")
        case .notLoaded: return Text("not loading")
        case .disabled: return Text("disabled")
        case nil: return Text("unknown")
        }
    }
}

// MARK: - Reclaimed this month

private struct ReclaimedCard: View {
    @EnvironmentObject var appState: AppState
    private static let slots = 12

    var body: some View {
        let runs = appState.cleanupsThisMonth
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Reclaimed this month")) {
                if !runs.isEmpty {
                    SiftStatusPill(Text("\(runs.count) runs"), tone: .success)
                }
            }
            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: SiftFormat.bytes(appState.freedThisMonth))
                        .siftStyle(.metricSmall)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        Group {
                            if let last = appState.cleanupHistory.first {
                                Text("last run \(SiftFormat.relative(last.date, to: timeline.date))")
                            } else {
                                Text("no cleanups yet")
                            }
                        }
                        .siftStyle(.monoSmall)
                        .lineLimit(1)
                    }
                }
                .fixedSize()
                runChart(runs)
            }
            Rectangle().fill(SiftColor.stroke).frame(height: 1)
            if appState.cleanupHistory.isEmpty {
                Text("Each cleanup and the space it freed shows up here.")
                    .siftStyle(.label)
            } else {
                VStack(spacing: 2) {
                    ForEach(appState.cleanupHistory.prefix(3)) { record in
                        HistoryRow(record: record)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface(.card)
    }

    /// One bar per run this month, oldest to newest; the newest is accented.
    /// Empty slots keep the chart's rhythm before twelve runs exist.
    private func runChart(_ runs: [CleanupRecord]) -> some View {
        let recent = Array(runs.prefix(Self.slots).reversed())
        let largest = max(recent.map(\.freedBytes).max() ?? 0, 1)
        let empty = Self.slots - recent.count
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<empty, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(SiftColor.track)
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
            }
            ForEach(Array(recent.enumerated()), id: \.offset) { index, run in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(index == recent.count - 1 ? SiftColor.accent : SiftColor.faint.opacity(0.7))
                    .frame(height: max(10, 58 * CGFloat(Double(run.freedBytes) / Double(largest))))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 58, alignment: .bottom)
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel(Text("Space freed by each cleanup this month"))
    }
}

private struct HistoryRow: View {
    let record: CleanupRecord

    var body: some View {
        HStack(spacing: 10) {
            SiftIcon.check.image(12)
                .foregroundStyle(SiftColor.success)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SiftColor.control))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: record.title ?? String(localized: "Cleanup"))
                    .font(.sift(12))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    subtitle(now: timeline.date)
                        .font(.sift(10.5))
                        .foregroundStyle(SiftColor.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: SiftFormat.bytes(record.freedBytes))
                .font(.siftMono(11.5))
                .foregroundStyle(SiftColor.accent)
        }
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }

    /// "Developer caches · 3 hours ago"; the group name when the record has a
    /// category, else just the time.
    private func subtitle(now: Date) -> Text {
        let when = SiftFormat.relative(record.date, to: now)
        guard let category = record.category, record.title != nil else { return Text(verbatim: when) }
        return Text("\(Text(category.cleanupTitle)) · \(when)")
    }
}
