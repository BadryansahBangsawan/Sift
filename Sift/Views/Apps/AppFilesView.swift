import AppKit
import SwiftUI

/// View-side grouping of discovered leftovers into CleanMyMac-style buckets.
/// Purely presentational — AppState's flat `discoveredFiles` stays the source
/// of truth so the removal/selection logic is untouched.
enum LeftoverGroup: String, CaseIterable, Identifiable {
    case application = "Application"
    case caches = "Caches"
    case appSupport = "Application Support"
    case preferences = "Preferences"
    case logs = "Logs"
    case containers = "Containers"
    case launchAgents = "Launch Agents"
    case other = "Other Files"

    var id: String { rawValue }

    /// The short kind label on a leftover row ("Support", "LaunchAgents").
    var shortLabel: LocalizedStringKey {
        switch self {
        case .application: return "Application"
        case .caches: return "Caches"
        case .appSupport: return "Support"
        case .preferences: return "Preferences"
        case .logs: return "Logs"
        case .containers: return "Containers"
        case .launchAgents: return "LaunchAgents"
        case .other: return "Other"
        }
    }

    static func categorize(_ url: URL) -> LeftoverGroup {
        let path = url.path
        if path.hasSuffix(".app") { return .application }
        if path.contains("/Caches/") { return .caches }
        if path.contains("/Application Support/") { return .appSupport }
        if path.contains("/Preferences/") { return .preferences }
        if path.contains("/Logs/") || path.contains("/DiagnosticReports/") { return .logs }
        if path.contains("/Containers/") || path.contains("/Group Containers/") { return .containers }
        if path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/") { return .launchAgents }
        return .other
    }
}

struct AppFilesView: View {
    @EnvironmentObject var appState: AppState
    let app: InstalledApp

    @State private var showBulkConfirmation = false
    @State private var pendingRemoval: Set<URL> = []
    @State private var dryRunPlan: UninstallPlan?
    @State private var appIsRunning = false
    /// One-pass size cache so the totals and rows don't re-stat the disk on
    /// every render.
    @State private var sizeCache: [URL: Int64] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 4

    private var appGuard: RunningAppGuard { RunningAppGuard(app: app) }

    private var totalSelectedSize: Int64 {
        appState.selectedFiles.reduce(Int64(0)) { $0 + (sizeCache[$1] ?? 0) }
    }

    private var totalDiscoveredSize: Int64 {
        appState.discoveredFiles.reduce(Int64(0)) { $0 + (sizeCache[$1] ?? 0) }
    }

    /// Discovered files ordered by kind, then path.
    private var orderedFiles: [(url: URL, group: LeftoverGroup)] {
        let order = Dictionary(uniqueKeysWithValues: LeftoverGroup.allCases.enumerated().map { ($1, $0) })
        return appState.discoveredFiles
            .map { ($0, LeftoverGroup.categorize($0)) }
            .sorted { lhs, rhs in
                let left = order[lhs.1, default: 0], right = order[rhs.1, default: 0]
                return left != right ? left < right : lhs.0.path < rhs.0.path
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Rectangle().fill(SiftColor.stroke).frame(height: 1)

            if appState.isScanningAppFiles {
                scanningState
            } else if appState.discoveredFiles.isEmpty {
                emptyState
            } else {
                leftoversHeading
                leftoversList
                    .layoutPriority(1)
                if appIsRunning {
                    runningBanner
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                actionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface(.card, padding: 24)
        .animation(reduceMotion ? nil : SiftMotion.quick, value: appIsRunning)
        .task(id: appState.discoveredFiles) {
            let urls = appState.discoveredFiles
            let task = Task.detached(priority: .utility) {
                var sizes: [URL: Int64] = [:]
                for url in urls {
                    guard !Task.isCancelled else { break }
                    sizes[url] = FileSizeCalculator.size(of: url) ?? 0
                }
                return sizes
            }
            let sizes = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
            guard !Task.isCancelled else { return }
            sizeCache = sizes
        }
        .onAppear { appIsRunning = appGuard.isRunning }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            appIsRunning = appGuard.isRunning
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            appIsRunning = appGuard.isRunning
        }
        .disabled(appState.isRemovingAppFiles)
        .confirmationDialog("Remove selected app files?", isPresented: $showBulkConfirmation, titleVisibility: .visible) {
            Button("Remove \(pendingRemoval.count) files", role: .destructive) {
                appState.removeSelectedFiles(confirmedURLs: pendingRemoval)
                pendingRemoval = []
            }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("Sift will move the selected app and related files to the Trash. Items requiring administrator authorization may be permanently deleted. Review the selection before continuing.")
        }
        .sheet(isPresented: Binding(
            get: { dryRunPlan != nil },
            set: { if !$0 { dryRunPlan = nil } }
        )) {
            if let plan = dryRunPlan {
                DryRunSheet(appName: app.appName, plan: plan) { dryRunPlan = nil }
            }
        }
        .onChange(of: appState.removalNeedsFullDiskAccess) { needs in
            // FDA-fixable removals jump straight into the rich sheet, the
            // same flow cleanup uses. The user grants permission once and we
            // re-fire the failed batch — using the frozen snapshot from
            // AppState so a mid-sheet selection change or app switch doesn't
            // re-trash the wrong files.
            guard needs else { return }
            let toRetry = appState.lastFailedRemovalURLs
            let items = toRetry.map { appState.makeUninstallCleanableItem(for: $0) }
            appState.removalError = nil
            appState.removalNeedsFullDiskAccess = false
            appState.lastFailedRemovalURLs = []
            appState.requestFullDiskAccessAndRetry(
                items: items,
                context: .uninstall(appName: app.appName, failedCount: items.count)
            )
        }
        .alert("Removal Failed", isPresented: Binding(
            get: { appState.removalError != nil && !appState.removalNeedsFullDiskAccess },
            set: {
                if !$0 {
                    appState.removalError = nil
                    appState.removalNeedsFullDiskAccess = false
                }
            }
        )) {
            Button("OK", role: .cancel) {
                appState.removalError = nil
                appState.removalNeedsFullDiskAccess = false
            }
        } message: {
            Text(appState.removalError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 18) {
            AppIconTile(app: app, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: app.appName)
                    .font(.siftDisplay(30))
                    .tracking(-0.6)
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                Text(verbatim: identityLine)
                    .font(.siftMono(11.5))
                    .foregroundStyle(SiftColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                locationLine
                    .font(.sift(11.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            if !appState.discoveredFiles.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: SiftFormat.bytes(totalDiscoveredSize))
                        .font(.siftDisplay(40))
                        .tracking(-1)
                        .foregroundStyle(SiftColor.textPrimary)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                    Text("app and leftovers")
                        .font(.sift(11.5))
                        .foregroundStyle(SiftColor.textTertiary)
                }
                .fixedSize()
            }
        }
    }

    /// "com.docker.docker, version 4.39.0".
    private var identityLine: String {
        guard let version = app.version else { return app.bundleIdentifier }
        return String(localized: "\(app.bundleIdentifier), version \(version)")
    }

    /// "/Applications/Docker.app, last opened 2 days ago".
    private var locationLine: Text {
        let path = (app.path.path as NSString).abbreviatingWithTildeInPath
        guard let lastOpened = app.lastOpened else { return Text(verbatim: path) }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: lastOpened, relativeTo: Date())
        return Text("\(path), last opened \(relative)")
    }

    // MARK: - States

    private var scanningState: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Scanning for related files...").siftStyle(.bodyStrong)
            Text(String(format: String(localized: "Checking %lld locations..."), Int64(appState.currentAppFileSearchLocationCount)))
                .siftStyle(.mono)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            SiftIconTile(icon: .check, tone: .success, size: 44)
            Text("No Related Files").siftStyle(.bodyStrong)
            Text(String(format: String(localized: "No additional files found for %@."), app.appName))
                .siftStyle(.label)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Leftovers

    private var leftoversHeading: some View {
        let allSelected = appState.selectedFiles.isSuperset(of: appState.discoveredFiles)
        return HStack(spacing: 10) {
            Text("Matched leftovers")
                .siftStyle(.cardTitle)
            Spacer(minLength: 8)
            Text("Matched by bundle identifier and app name")
                .font(.sift(11))
                .foregroundStyle(SiftColor.textTertiary)
                .lineLimit(1)
            Button(allSelected ? "Deselect All" : "Select All") {
                if allSelected {
                    appState.selectedFiles.removeAll()
                } else {
                    appState.selectedFiles = Set(appState.discoveredFiles)
                }
            }
            .buttonStyle(.siftQuiet)
        }
    }

    /// Sized to its rows so the banner sits right under the list; scrolls
    /// once the rows outgrow the card.
    private var leftoversList: some View {
        let files = orderedFiles
        let contentHeight = CGFloat(files.count) * Self.rowHeight + CGFloat(max(files.count - 1, 0)) * Self.rowSpacing
        return ScrollView {
            VStack(spacing: Self.rowSpacing) {
                ForEach(files, id: \.url) { file in
                    LeftoverRow(
                        url: file.url,
                        group: file.group,
                        isSelected: fileSelectionBinding(for: file.url),
                        size: sizeCache[file.url],
                        onRemove: { removeSingleFile(file.url) }
                    )
                    .frame(height: Self.rowHeight)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .scrollIndicators(.automatic)
        .frame(minHeight: min(contentHeight, Self.rowHeight * 2), maxHeight: contentHeight)
    }

    private var runningBanner: some View {
        HStack(spacing: 12) {
            SiftIcon.triangleAlert.image(16).foregroundStyle(SiftColor.warning)
            Text("Quit \(app.appName) before removing. Files move to the Trash.")
                .font(.sift(12.5))
                .foregroundStyle(SiftColor.cautionText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                appGuard.requestQuit()
            } label: {
                Text("Quit \(app.appName)")
                    .font(.sift(12, weight: 500))
                    .foregroundStyle(SiftColor.warning)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule(style: .continuous).fill(SiftColor.cautionButton))
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("uninstaller.quitApp")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SiftColor.cautionBackground))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SiftColor.cautionStroke, lineWidth: 1))
    }

    // MARK: - Action bar

    private var actionBar: some View {
        UninstallerActionBar(
            summary: UninstallerActionBar.summary(count: appState.selectedFiles.count, size: totalSelectedSize),
            canDryRun: !appState.selectedFiles.isEmpty,
            canReview: !appState.selectedFiles.isEmpty && !appIsRunning,
            runningAppName: appIsRunning ? app.appName : nil,
            showInFinder: { NSWorkspace.shared.activateFileViewerSelecting([app.path]) },
            dryRun: { dryRunPlan = UninstallPlan(files: appState.selectedFiles, sizeOf: { sizeCache[$0] }) },
            review: {
                pendingRemoval = appState.selectedFiles
                showBulkConfirmation = true
            }
        )
    }

    // MARK: - Helpers

    private func fileSelectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { appState.selectedFiles.contains(url) },
            set: { selected in
                if selected {
                    appState.selectedFiles.insert(url)
                } else {
                    appState.selectedFiles.remove(url)
                }
            }
        )
    }

    private func removeSingleFile(_ url: URL) {
        appState.selectedFiles = [url]
        appState.removeSelectedFiles()
    }
}

// MARK: - Leftover row

private struct LeftoverRow: View {
    let url: URL
    let group: LeftoverGroup
    @Binding var isSelected: Bool
    let size: Int64?
    let onRemove: () -> Void

    @State private var showConfirmation = false

    var body: some View {
        HStack(spacing: 14) {
            Toggle(isOn: $isSelected) { EmptyView() }
                .toggleStyle(.siftCheckbox)
                .labelsHidden()
                .accessibilityLabel(Text(verbatim: url.lastPathComponent))
            SiftTag(text: Text(group.shortLabel), accented: group == .application)
                .frame(width: 120, alignment: .leading)
            Text(verbatim: (url.path as NSString).abbreviatingWithTildeInPath)
                .font(.siftMono(11.5))
                .foregroundStyle(SiftColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(url.path)
            Text(verbatim: size.map(SiftFormat.bytes) ?? "…")
                .font(.siftMono(12))
                .foregroundStyle(SiftColor.textSecondary)
                .lineLimit(1)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .siftRowBackground()
        .onTapGesture { isSelected.toggle() }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
            Button("Remove this file") { showConfirmation = true }
        }
        .alert(
            Text(String(format: String(localized: "Remove %@?"), url.lastPathComponent)),
            isPresented: $showConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { onRemove() }
        } message: {
            Text("The file moves to the Trash. Items that need administrator authorization are deleted permanently.")
        }
    }
}

// MARK: - Dry run

private struct DryRunSheet: View {
    let appName: String
    let plan: UninstallPlan
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dry run").siftStyle(.label)
                Text("What removing \(appName) would touch")
                    .font(.siftDisplay(26))
                    .tracking(-0.5)
                    .foregroundStyle(SiftColor.textPrimary)
            }
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(plan.entries) { entry in
                        HStack(spacing: 14) {
                            SiftTag(text: Text(entry.group.shortLabel), accented: entry.group == .application)
                                .frame(width: 120, alignment: .leading)
                            Text(verbatim: (entry.url.path as NSString).abbreviatingWithTildeInPath)
                                .font(.siftMono(11.5))
                                .foregroundStyle(SiftColor.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                            Text(verbatim: SiftFormat.bytes(entry.size))
                                .font(.siftMono(12))
                                .foregroundStyle(SiftColor.textSecondary)
                                .frame(width: 72, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .siftRowBackground()
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 360)
            HStack(spacing: 12) {
                SiftFootnote(Text("Nothing has been removed."))
                Spacer()
                Text(verbatim: UninstallerActionBar.summary(count: plan.entries.count, size: plan.totalSize))
                    .font(.siftMono(12))
                    .foregroundStyle(SiftColor.textTertiary)
                Button("Done", action: dismiss)
                    .buttonStyle(.siftPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(SiftColor.card)
    }
}
