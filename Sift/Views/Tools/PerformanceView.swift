import AppKit
import SwiftUI

struct PerformanceView: View {
    private enum LoadState {
        case idle
        case loading
        case loaded(PerformanceInspection)
        case failed(String)
    }

    /// Matches the "samples every 2 seconds" eyebrow.
    private static let samplingInterval: TimeInterval = 2
    /// Startup rows shown before "Show all".
    private static let startupPreviewCount = 5
    private static let startupCardID = "performance.startupCard"

    @ObservedObject private var monitor = SystemMonitor.shared
    @State private var state: LoadState = .idle
    @State private var resourcesExpanded = false
    @State private var monitorOwner = UUID()
    @State private var pageIsVisible = false
    @State private var appIsActive = NSApplication.shared.isActive
    @State private var windowIsMinimized = false
    @State private var windowIsKey = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startupShowsAll = false
    @State private var startupHighlighted = false
    @State private var issuesExpanded = false
    @State private var snapshotPendingDeletion: PerformanceSnapshot?
    @State private var deletingSnapshotID: String?
    @State private var deletionError: String?
    @State private var batteryStatus: BatteryStatus?
    @State private var togglingLabel: String?
    @State private var startupToggleError: String?
    private let inspector = PerformanceInspector()
    private let batteryInspector = BatteryInspector()

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
                    header(scroller)
                    HStack(alignment: .top, spacing: SiftSpacing.gutter) {
                        processorCard
                        memoryCard
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if batteryStatus?.isInstalled == true {
                        batteryCard
                    }
                    inspectionContent
                    processesCard
                }
            }
            .scrollIndicators(.never)
        }
        .task {
            await refresh()
            await refreshBattery()
        }
        .onAppear {
            pageIsVisible = true
            appIsActive = NSApplication.shared.isActive
            windowIsMinimized = WindowOpener.shared.mainWindow?.isMiniaturized ?? false
            windowIsKey = WindowOpener.shared.mainWindow?.isKeyWindow ?? false
            synchronizeMonitoring()
        }
        .onDisappear {
            pageIsVisible = false
            synchronizeMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appIsActive = true
            synchronizeMonitoring()
            // The battery card has no live feed: re-read it whenever the user
            // comes back, otherwise it shows whatever it said at first paint.
            Task { await refreshBattery() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appIsActive = false
            synchronizeMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === WindowOpener.shared.mainWindow else { return }
            windowIsMinimized = true
            synchronizeMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === WindowOpener.shared.mainWindow else { return }
            windowIsMinimized = false
            synchronizeMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === WindowOpener.shared.mainWindow else { return }
            windowIsKey = true
            synchronizeMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === WindowOpener.shared.mainWindow else { return }
            windowIsKey = false
            synchronizeMonitoring()
        }
        .alert("Delete local snapshot?", isPresented: deletionConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                snapshotPendingDeletion = nil
            }
            Button("Delete Snapshot", role: .destructive) {
                guard let snapshot = snapshotPendingDeletion else { return }
                snapshotPendingDeletion = nil
                Task { await delete(snapshot) }
            }
        } message: {
            Text(snapshotDeletionMessage)
        }
        .alert("Snapshot could not be deleted", isPresented: deletionErrorPresented) {
            Button("OK", role: .cancel) {
                deletionError = nil
            }
        } message: {
            Text(deletionError ?? String(localized: "Unknown error"))
        }
        .alert("Launch item could not be changed", isPresented: startupToggleErrorPresented) {
            Button("OK", role: .cancel) {
                startupToggleError = nil
            }
        } message: {
            Text(startupToggleError ?? String(localized: "Unknown error"))
        }
    }

    // MARK: - Header

    /// SiftPageHeader's layout, with a live dot in the eyebrow.
    private func header(_ scroller: ScrollViewProxy) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                liveEyebrow
                Text("Performance").siftStyle(.pageTitle).lineLimit(1)
            }
            Spacer(minLength: 16)
            HStack(spacing: 8) {
                Button {
                    Task {
                        await refresh()
                        await refreshBattery()
                    }
                } label: {
                    headerButtonLabel("Refresh", icon: .rotateCw)
                }
                .buttonStyle(.siftSecondary)
                .disabled(isLoading)
                .help("Inspect startup items and local snapshots again")

                Button {
                    showStartupItems(scroller)
                } label: {
                    headerButtonLabel("Startup items", icon: .power)
                }
                .buttonStyle(.siftSecondary)
                .help("Jump to the startup items")
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var liveEyebrow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(resourcesAreActive ? SiftColor.success : SiftColor.textTertiary)
                .frame(width: 8, height: 8)
                .background(
                    Circle()
                        .fill((resourcesAreActive ? SiftColor.success : SiftColor.textTertiary).opacity(0.27))
                        .padding(-3)
                )
            Text(resourcesAreActive ? "Live, samples every 2 seconds" : "Paused while Sift is in the background")
                .siftStyle(.label)
        }
    }

    private func headerButtonLabel(_ title: LocalizedStringKey, icon: SiftIcon) -> some View {
        HStack(spacing: 8) {
            icon.image(15).foregroundStyle(SiftColor.textSecondary)
            Text(title)
        }
    }

    private func showStartupItems(_ scroller: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : SiftMotion.snappy) {
            scroller.scrollTo(Self.startupCardID, anchor: .top)
        }
        withAnimation(SiftMotion.quick) { startupHighlighted = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.4)) { startupHighlighted = false }
        }
    }

    // MARK: - Processor and memory

    private var processorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Processor"), icon: .cpu) {
                SiftStatusPill(Text("\(percent(monitor.cpuUsage))% busy"), tone: monitor.cpuUsage >= 0.85 ? .warning : .success)
            }
            HStack(alignment: .bottom, spacing: 24) {
                SiftMetric("\(percent(monitor.cpuUsage))%", caption: Text("of \(ProcessInfo.processInfo.activeProcessorCount) cores"))
                    .fixedSize()
                SiftHistoryBars(values: monitor.cpuHistory)
            }
            HStack(spacing: 8) {
                SiftChip(Text("User"), value: "\(percent(monitor.cpuUser))%")
                SiftChip(Text("System"), value: "\(percent(monitor.cpuSystem))%")
                SiftChip(Text("Idle"), value: "\(percent(monitor.cpuIdle))%")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface()
        .accessibilityElement(children: .contain)
    }

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Memory"), icon: .memoryStick) {
                SiftStatusPill(
                    Text("\(bytes(monitor.memoryUsed)) of \(bytes(monitor.memoryTotal))"),
                    tone: .accent
                )
            }
            SiftMetric("\(percent(monitor.memoryFraction))%", caption: Text("wired, active and compressed"))
            memoryBar
            // Narrow windows drop the labels before the chips would overflow;
            // the dot colors still match the bar.
            ViewThatFits(in: .horizontal) {
                memoryLegend(showsLabels: true, compact: false)
                memoryLegend(showsLabels: true, compact: true)
                memoryLegend(showsLabels: false, compact: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface()
        .accessibilityElement(children: .contain)
    }

    private func memoryLegend(showsLabels: Bool, compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            SiftLegendChip(color: SiftColor.accent, label: Text("Wired"), value: bytes(monitor.memoryWired), showsLabel: showsLabels, compact: compact)
            SiftLegendChip(color: SiftColor.memoryActive, label: Text("Active"), value: bytes(monitor.memoryActive), showsLabel: showsLabels, compact: compact)
            SiftLegendChip(color: SiftColor.memoryCompressed, label: Text("Compressed"), value: bytes(monitor.memoryCompressed), showsLabel: showsLabels, compact: compact)
            SiftLegendChip(color: SiftColor.memoryFreeDot, label: Text("Free"), value: bytes(unusedMemory), showsLabel: showsLabels, compact: compact)
        }
    }

    /// Wired, active and compressed scaled to total memory; the last segment
    /// is everything else.
    private var memoryBar: some View {
        GeometryReader { proxy in
            let total = Double(max(monitor.memoryTotal, 1))
            let spacing: CGFloat = 3
            let usable = max(proxy.size.width - spacing * 3, 0)
            let parts: [(Int64, Color)] = [
                (monitor.memoryWired, SiftColor.accent),
                (monitor.memoryActive, SiftColor.memoryActive),
                (monitor.memoryCompressed, SiftColor.memoryCompressed),
            ]
            HStack(spacing: spacing) {
                ForEach(parts.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(parts[index].1)
                        .frame(width: max(0, usable * CGFloat(Double(parts[index].0) / total)))
                }
                Capsule(style: .continuous)
                    .fill(SiftColor.meterUsed)
                    .frame(maxWidth: .infinity)
            }
            .animation(SiftMotion.quick, value: monitor.memoryUsed)
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel(Text("Memory in use"))
        .accessibilityValue(Text("\(percent(monitor.memoryFraction))%"))
    }

    /// Memory not wired, active or compressed, so the legend adds up to the total.
    private var unusedMemory: Int64 {
        max(0, monitor.memoryTotal - monitor.memoryUsed)
    }

    // MARK: - Battery

    /// Hidden entirely on Macs without a battery — a card that reads "no
    /// battery" is noise on a desktop, not information.
    private var batteryCard: some View {
        let status = batteryStatus ?? .notInstalled
        return VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Battery"), icon: .batteryCharging) {
                Text("Read from IOKit and pmset at every page visit")
                    .font(.sift(11.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(1)
            }
            HStack(alignment: .top, spacing: 12) {
                batteryPanel(title: Text("Charge"), pill: chargePill(status)) {
                    SiftMetric(status.chargePercent.map { "\($0)%" } ?? "–", caption: Text("charged"))
                    SiftSegmentBar(filled: Int((Double(status.chargePercent ?? 0) / 5).rounded()))
                    Text(verbatim: chargeDetail(status) ?? " ")
                        .siftStyle(.monoSmall)
                }
                batteryPanel(title: Text("Health"), pill: nil) {
                    SiftMetric(status.healthPercent.map { "\($0)%" } ?? "–", caption: Text("of design"))
                    SiftPanelBar(
                        fraction: Double(status.healthPercent ?? 0) / 100,
                        fill: (status.healthPercent ?? 100) < 80 ? SiftColor.warning : SiftColor.accent
                    )
                    healthDetail(status).siftStyle(.monoSmall)
                }
                batteryPanel(title: Text("Cycles"), pill: nil) {
                    SiftMetric(status.cycleCount.map { "\($0)" } ?? "–", caption: Text("counted"))
                    SiftPanelBar(fraction: Double(status.cycleCount ?? 0) / 1000)
                    Text("rated for 1000 cycles").siftStyle(.monoSmall)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .siftSurface()
    }

    private func batteryPanel<Content: View>(
        title: Text,
        pill: SiftStatusPill?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                title.font(.sift(12)).foregroundStyle(SiftColor.textSecondary)
                Spacer(minLength: 8)
                if let pill { pill }
            }
            content()
        }
        .lineLimit(1)
        .frame(maxHeight: .infinity, alignment: .top)
        .siftInsetPanel()
    }

    private func chargePill(_ status: BatteryStatus) -> SiftStatusPill? {
        guard let charging = status.isCharging else { return nil }
        if charging, let charge = status.chargePercent, charge >= 100 {
            return SiftStatusPill(Text("Fully charged"), tone: .success)
        }
        if charging { return SiftStatusPill(Text("Charging"), tone: .success) }
        if status.isOnACPower == true { return SiftStatusPill(Text("Not charging"), tone: .neutral) }
        return SiftStatusPill(Text("On battery"), tone: .warning)
    }

    /// "1h 12m to full, AC power". The time part is left out when macOS has no estimate.
    private func chargeDetail(_ status: BatteryStatus) -> String? {
        var parts: [String] = []
        if status.isCharging == true, let minutes = status.minutesToFull, minutes > 0 {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
            formatter.unitsStyle = .abbreviated
            if let duration = formatter.string(from: TimeInterval(minutes * 60)) {
                parts.append(String(localized: "\(duration) to full"))
            }
        }
        switch status.isOnACPower {
        case true?: parts.append(String(localized: "AC power"))
        case false?: parts.append(String(localized: "battery power"))
        case nil: break
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// "4057 of 4629 mAh", with the service threshold named only when the
    /// health percentage is actually below it. The card shows that percentage
    /// directly above this line, so a fixed suffix contradicted it.
    static func batteryHealthDetail(_ status: BatteryStatus) -> String {
        let needsService = (status.healthPercent ?? 100) < 80
        if let max = status.maxCapacityMAh, let design = status.designCapacityMAh {
            // Plain digits, as the design writes capacities ("4082 of 4629 mAh").
            if needsService {
                // One key, so a translation can put the threshold before the
                // capacities if its word order needs that.
                return String(localized: "\(String(max)) of \(String(design)) mAh, service below 80%")
            }
            return String(localized: "\(String(max)) of \(String(design)) mAh")
        }
        return needsService ? String(localized: "service below 80%") : ""
    }

    private func healthDetail(_ status: BatteryStatus) -> Text {
        Text(verbatim: Self.batteryHealthDetail(status))
    }

    @MainActor
    private func refreshBattery() async {
        let status = await batteryInspector.inspect()
        guard !Task.isCancelled else { return }
        batteryStatus = status
    }

    // MARK: - Monitoring lifecycle

    private var resourcesAreActive: Bool {
        pageIsVisible && appIsActive && windowIsKey && !windowIsMinimized
    }

    private func synchronizeMonitoring() {
        if resourcesAreActive {
            monitor.start(owner: monitorOwner, interval: Self.samplingInterval)
        } else {
            monitor.stop(owner: monitorOwner)
        }
    }

    // MARK: - Startup items and snapshots

    @ViewBuilder
    private var inspectionContent: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Inspecting startup items and local snapshots…")
                    .siftStyle(.body)
                Spacer()
            }
            .siftSurface()
        case .loaded(let inspection):
            if !inspection.issues.isEmpty {
                issuesCard(inspection.issues)
            }
            HStack(alignment: .top, spacing: SiftSpacing.gutter) {
                startupCard(inspection.startupItems)
                snapshotsCard(inspection.snapshots)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            HStack(alignment: .center, spacing: 12) {
                SiftIconTile(icon: .triangleAlert, tone: .warning, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inspection stopped").siftStyle(.bodyStrong)
                    Text(message).siftStyle(.label).textSelection(.enabled)
                }
                Spacer()
                Button("Try Again") {
                    Task { await refresh() }
                }
                .buttonStyle(.siftSecondary)
            }
            .siftSurface()
        }
    }

    private func issuesCard(_ issues: [PerformanceInspectionIssue]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : SiftMotion.snappy) { issuesExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    SiftIcon.triangleAlert.image(16).foregroundStyle(SiftColor.warning)
                    Text("Some information could not be read (\(issues.count))")
                        .font(.sift(12.5))
                        .foregroundStyle(SiftColor.cautionText)
                    Spacer()
                    SiftIcon.chevronDown.image(13)
                        .foregroundStyle(SiftColor.warning)
                        .rotationEffect(.degrees(issuesExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(LocalizedStringKey(issuesExpanded ? "Expanded" : "Collapsed")))

            if issuesExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title).font(.sift(12, weight: 500)).foregroundStyle(SiftColor.textPrimary)
                            Text(issue.detail).siftStyle(.monoSmall).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SiftColor.cautionBackground))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SiftColor.cautionStroke, lineWidth: 1))
    }

    private func startupCard(_ items: [PerformanceStartupItem]) -> some View {
        let visible = startupShowsAll ? items : Array(items.prefix(Self.startupPreviewCount))
        return VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Startup items"), icon: .power) {
                Text("\(items.count) registered").siftStyle(.mono)
            }
            if items.isEmpty {
                SiftFootnote(Text("No launch agents or daemons were found outside macOS system folders."), icon: .check)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(visible) { item in
                        StartupItemRow(
                            item: item,
                            isBusy: togglingLabel == item.label,
                            onToggle: item.domain == .userAgent
                                ? { toggleStartupItem(item) }
                                : nil
                        ) {
                            reveal(item.sourceURL)
                        }
                    }
                }
                if items.count > Self.startupPreviewCount {
                    Button {
                        withAnimation(reduceMotion ? nil : SiftMotion.snappy) { startupShowsAll.toggle() }
                    } label: {
                        Text(startupShowsAll ? "Show fewer" : "Show all \(items.count)")
                    }
                    .buttonStyle(.siftQuiet)
                    .padding(.leading, 2)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                footnote(Text("Only agents in your Library can be switched off"))
                Spacer(minLength: 8)
                Button("Login Items Settings") { openLoginItemsSettings() }
                    .buttonStyle(.siftQuiet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface()
        .overlay(
            RoundedRectangle(cornerRadius: SiftRadius.card, style: .continuous)
                .strokeBorder(SiftColor.accent, lineWidth: 1.5)
                .opacity(startupHighlighted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .id(Self.startupCardID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("performance.startupDisclosure")
    }

    private func snapshotsCard(_ snapshots: [PerformanceSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Local snapshots"), icon: .history) {
                Button {
                    openTimeMachineSettings()
                } label: {
                    Text("Time Machine")
                        .font(.sift(11))
                        .foregroundStyle(SiftColor.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Open Time Machine settings")
            }
            if snapshots.isEmpty {
                SiftFootnote(Text("Time Machine did not report any snapshots for the startup disk."), icon: .check)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        SnapshotRow(
                            snapshot: snapshot,
                            emphasized: index == 0,
                            isDeleting: deletingSnapshotID == snapshot.id,
                            deletionInProgress: deletingSnapshotID != nil
                        ) {
                            snapshotPendingDeletion = snapshot
                        }
                    }
                }
            }
            footnote(Text("Snapshots are thinned by macOS after 24 hours"))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface()
        .accessibilityElement(children: .contain)
    }

    /// The design's card footnote: 13 pt info icon, 11.5 pt tertiary text.
    private func footnote(_ text: Text) -> some View {
        HStack(spacing: 8) {
            SiftIcon.info.image(13).foregroundStyle(SiftColor.textTertiary)
            text.font(.sift(11.5)).foregroundStyle(SiftColor.textTertiary)
        }
    }

    // MARK: - Processes

    private var processesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SiftCardHeader(Text("Processes"), icon: .activity) {
                HStack(spacing: 6) {
                    Button("Activity Monitor") { openActivityMonitor() }
                        .buttonStyle(.siftQuiet)
                    Button {
                        withAnimation(reduceMotion ? nil : SiftMotion.snappy) { resourcesExpanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(resourcesExpanded ? "Hide" : "Show")
                            SiftIcon.chevronDown.image(12)
                                .rotationEffect(.degrees(resourcesExpanded ? 180 : 0))
                        }
                    }
                    .buttonStyle(.sift(.secondary, compact: true))
                    .accessibilityLabel(Text("Processes"))
                    .accessibilityValue(Text(LocalizedStringKey(resourcesExpanded ? "Expanded" : "Collapsed")))
                    .accessibilityIdentifier("performance.resourcesDisclosure")
                }
            }
            if resourcesExpanded {
                ProcessResourcesView(isActive: resourcesAreActive)
            }
        }
        .siftSurface()
        .padding(.bottom, 2)
    }

    // MARK: - Formatting

    private func percent(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    /// "15.9 GB" with one decimal, as the design writes memory sizes; a dash
    /// until the monitor has taken its first sample.
    private func bytes(_ value: Int64) -> String {
        guard monitor.memoryTotal > 0 else { return "–" }
        return Self.memorySize(value)
    }

    /// Binary gigabytes with at most one decimal ("15.9 GB", "16 GB"), as
    /// ByteCountFormatter's memory style counts them; megabytes below 1 GB.
    static func memorySize(_ value: Int64) -> String {
        let gigabytes = Double(value) / 1_073_741_824
        let (amount, unit): (Double, UnitInformationStorage) = gigabytes >= 1
            ? (gigabytes, .gigabytes)
            : (Double(value) / 1_048_576, .megabytes)
        return Measurement(value: amount, unit: unit).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(0...(unit == .gigabytes ? 1 : 0))))
        )
    }

    private var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private var deletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { snapshotPendingDeletion != nil },
            set: { if !$0 { snapshotPendingDeletion = nil } }
        )
    }

    private var snapshotDeletionMessage: String {
        guard let snapshot = snapshotPendingDeletion else {
            return String(localized: "This permanently removes the selected Time Machine snapshot.")
        }
        return String(localized: "This permanently removes \(snapshot.identifier). Its size is unknown, and the action cannot be undone.")
    }

    private var deletionErrorPresented: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )
    }

    @MainActor
    private var startupToggleErrorPresented: Binding<Bool> {
        Binding(
            get: { startupToggleError != nil },
            set: { presented in
                if !presented { startupToggleError = nil }
            }
        )
    }

    // MARK: - Actions

    private func toggleStartupItem(_ item: PerformanceStartupItem) {
        guard togglingLabel == nil else { return }
        togglingLabel = item.label
        Task {
            do {
                try await inspector.setStartupItem(item, disabled: !item.isDisabled)
                await refresh()
            } catch {
                startupToggleError = error.localizedDescription
            }
            togglingLabel = nil
        }
    }

    private func refresh() async {
        guard !isLoading else { return }
        state = .loading
        do {
            state = .loaded(try await inspector.inspect())
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func delete(_ snapshot: PerformanceSnapshot) async {
        guard deletingSnapshotID == nil else { return }
        deletingSnapshotID = snapshot.id
        defer { deletingSnapshotID = nil }
        do {
            try await inspector.deleteSnapshot(snapshot)
            state = .loaded(try await inspector.inspect())
        } catch is CancellationError {
            return
        } catch {
            deletionError = error.localizedDescription
        }
    }

    private func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openTimeMachineSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.TimeMachine-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Rows

private struct StartupItemRow: View {
    let item: PerformanceStartupItem
    var isBusy: Bool = false
    /// nil for anything the app is not allowed to toggle (system agents and
    /// daemons), which renders no switch at all.
    var onToggle: (() -> Void)?
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.label)
                    .font(.sift(12.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(.siftMono(10.5))
                    .foregroundStyle(item.status == .notLoaded ? SiftColor.warning : SiftColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let onToggle {
                Toggle(isOn: Binding(
                    get: { !item.isDisabled },
                    set: { _ in onToggle() }
                )) { EmptyView() }
                    .toggleStyle(.siftSwitch)
                    .labelsHidden()
                    .disabled(isBusy)
                    .accessibilityLabel(Text(verbatim: item.label))
                    .help("Enable or disable this launch agent at login")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .siftRowBackground()
        .help(item.program ?? item.sourceURL.path)
        .contextMenu {
            Button("Reveal plist in Finder", action: onReveal)
        }
        .onTapGesture(count: 2, perform: onReveal)
    }

    private var statusColor: Color {
        switch item.status {
        case .loaded: return SiftColor.success
        case .notLoaded: return SiftColor.warning
        case .disabled: return SiftColor.faint
        case nil: return SiftColor.textTertiary
        }
    }

    private var statusText: LocalizedStringKey {
        switch item.status {
        case .loaded: return "loaded by launchd"
        case .notLoaded: return "plist present, not loaded"
        case .disabled: return "disabled"
        case nil: return item.domain == .userAgent ? "user agent" : "system item"
        }
    }
}

private struct SnapshotRow: View {
    let snapshot: PerformanceSnapshot
    /// The newest snapshot carries the warning-tinted button, as in the design.
    let emphasized: Bool
    let isDeleting: Bool
    let deletionInProgress: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: displayName)
                    .font(.siftMono(12))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(verbatim: relativeDate)
                    .font(.sift(11))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(1)
            }
            .help(snapshot.identifier)
            Spacer(minLength: 8)
            if PerformanceInspector.deletionTimestamp(for: snapshot) != nil {
                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        if isDeleting {
                            ProgressView().controlSize(.mini)
                        } else {
                            SiftIcon.trash2.image(13)
                                .foregroundStyle(emphasized ? SiftColor.warning : SiftColor.textSecondary)
                        }
                        Text("Delete")
                    }
                }
                .buttonStyle(.sift(emphasized ? .destructive : .secondary, compact: true))
                .disabled(deletionInProgress)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SiftColor.control))
    }

    /// The identifier without its ".local" suffix; the time stays because
    /// Time Machine keeps several snapshots a day.
    private var displayName: String {
        snapshot.identifier.hasSuffix(".local")
            ? String(snapshot.identifier.dropLast(".local".count))
            : snapshot.identifier
    }

    /// "today, 08:15", "yesterday, 21:00", "1 week ago, 10:30". No size:
    /// macOS does not report a reliable per-snapshot size.
    private var relativeDate: String {
        guard let date = snapshot.date else { return snapshot.kind.title }
        return "\(relativeDay(date)), \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        var components = DateComponents()
        if days >= 7 {
            components.weekOfMonth = -(days / 7)
        } else {
            components.day = -max(days, 0)
        }
        return formatter.localizedString(from: components)
    }
}
