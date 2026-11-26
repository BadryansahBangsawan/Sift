import SwiftUI

struct OrphanListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedOrphans: Set<URL> = []
    @State private var isRemoving = false
    @State private var showRemovalConfirmation = false
    @State private var pendingRemoval: Set<URL> = []
    @State private var removalErrorMessage: String?
    /// Orphan sizes computed off the main thread. Orphans are exactly the large
    /// leftovers (multi-GB Caches/Containers/Application Support), and their
    /// size is a recursive directory walk — calling it from `body` would re-walk
    /// every realized row on each selection toggle and beachball the UI. We walk
    /// once off-main per result set and rows read the cached value.
    @State private var sizeCache: [URL: Int64] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
            header

            Group {
                if appState.isSearchingOrphans {
                    VStack(spacing: 14) {
                        SiftIconTile(icon: .scanSearch, tone: .accent, size: 48)
                        ProgressView(LocalizedStringKey("Scanning for orphaned files..."))
                            .progressViewStyle(.linear)
                            .tint(SiftColor.accent)
                            .font(.sift(13))
                            .foregroundStyle(SiftColor.textSecondary)
                            .frame(maxWidth: 300)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .siftSurface(.card)
                } else if !appState.orphanScanCompleted {
                    // Nothing has been scanned yet: "No Orphaned Files" would
                    // claim the app looked and found none.
                    EmptyStateView(
                        "Not scanned yet",
                        systemImage: "magnifyingglass",
                        description: "Scan to see whether uninstalled apps left files behind.",
                        action: { appState.findOrphans() },
                        actionLabel: "Scan for leftover files",
                        tint: SiftColor.textSecondary
                    )
                    .siftSurface(.card)
                } else if !appState.orphanedFiles.isEmpty {
                    table
                } else if appState.orphanScanNeedsAppList {
                    EmptyStateView(
                        "Couldn't compare installed apps",
                        systemImage: "exclamationmark.triangle",
                        description: "Sift needs the list of installed apps before it can call a file a leftover. Try again in a moment.",
                        action: { appState.findOrphans() },
                        actionLabel: "Scan for leftover files",
                        tint: SiftColor.warning
                    )
                    .siftSurface(.card)
                } else {
                    EmptyStateView("No Leftovers", systemImage: "checkmark.circle", description: "No leftover files from uninstalled apps were found.", action: { appState.findOrphans() }, actionLabel: "Scan for leftover files", tint: SiftColor.success)
                        .siftSurface(.card)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !appState.orphanedFiles.isEmpty && !appState.isSearchingOrphans {
                selectionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(orphanedFilesTitle)
        .task(id: appState.orphanedFiles) {
            // Recompute off the main thread whenever the orphan set changes
            // (new scan, removals). FileSizeCalculator is a plain static helper
            // with no main-actor isolation, so it runs safely on a detached
            // background task; the result is applied back on the main actor.
            let urls = appState.orphanedFiles
            let sizes = await Task.detached(priority: .utility) { () -> [URL: Int64] in
                var out: [URL: Int64] = [:]
                for url in urls {
                    out[url] = FileSizeCalculator.size(of: url) ?? 0
                }
                return out
            }.value
            sizeCache = sizes        }
        .confirmationDialog("Remove selected leftovers?", isPresented: $showRemovalConfirmation, titleVisibility: .visible) {
            Button("Remove \(pendingRemoval.count) items", role: .destructive) {
                let batch = pendingRemoval
                pendingRemoval = []
                Task { await removeSelectedOrphans(batch) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
        } message: {
            Text("Files will be moved to the Trash. Items requiring administrator authorization may be permanently deleted. App matching is a best-effort estimate; review files you recognize before removing them.")
        }
        .alert("Some files could not be removed", isPresented: Binding(
            get: { removalErrorMessage != nil },
            set: { if !$0 { removalErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(removalErrorMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        SiftScreenHeader(
            Text("Leftovers"),
            eyebrow: Text(orphanedFilesTitle)
        ) {
            // The empty state carries its own Scan button.
            if !appState.orphanedFiles.isEmpty || appState.isSearchingOrphans {
                Button {
                    appState.findOrphans()
                } label: {
                    Label {
                        Text("Scan for leftover files")
                    } icon: {
                        SiftIcon.rotateCw.image(15).foregroundStyle(SiftColor.textSecondary)
                    }
                }
                .buttonStyle(.siftSecondary)
                .disabled(appState.isSearchingOrphans)
            }
        }    }

    // MARK: Table

    private var table: some View {
        VStack(spacing: 2) {
            SiftTableHeader {
                Color.clear.frame(width: 20, height: 1)
                Color.clear.frame(width: 36, height: 1)
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    Text("Size")
                    SiftIcon.arrowDown.image(12)
                }
                .foregroundStyle(SiftColor.textSecondary)
                .frame(width: 90, alignment: .trailing)
            }

            ScrollView {
                // No .staggered(): rows are lazy, so a delayed reveal would
                // blank each row as it scrolls in. The removal transition
                // below still gives the sweep-out on delete.
                LazyVStack(spacing: 2) {
                    ForEach(appState.orphanedFiles, id: \.self) { fileURL in
                        OrphanRowView(
                            fileURL: fileURL,
                            isSelected: orphanBinding(for: fileURL),
                            fileSize: sizeCache[fileURL],
                            onReveal: { revealInFinder(fileURL) },
                            onCopyPath: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(fileURL.path, forType: .string)
                            },
                            onIgnore: { ignoreOrphans([fileURL]) },
                            onTrash: {
                                pendingRemoval = [fileURL]
                                showRemovalConfirmation = true
                            }
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .asymmetric(
                                    insertion: .opacity,
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .siftSurface(.card, padding: 10)
    }

    // MARK: Selection bar

    private var selectionBar: some View {
        let allSelected = selectedOrphans.count == appState.orphanedFiles.count
        let selectedSize = selectedOrphans.reduce(Int64(0)) { $0 + (sizeCache[$1] ?? 0) }
        return SiftSelectionBar(count: selectedOrphans.count) {
            HStack(spacing: 10) {
                Text("selected")
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                if !selectedOrphans.isEmpty {
                    Text(verbatim: SiftFormat.bytes(selectedSize))
                        .font(.siftMono(12.5))
                        .foregroundStyle(SiftColor.accent)
                }
            }
            .lineLimit(1)
        } actions: {
            Button(LocalizedStringKey(allSelected ? "Deselect All" : "Select All")) {
                if allSelected {
                    selectedOrphans.removeAll()
                } else {
                    selectedOrphans = Set(appState.orphanedFiles)
                }
            }
            .buttonStyle(.sift(.quiet))

            if !selectedOrphans.isEmpty {
                Button(ignoreSelectedLabel) {
                    ignoreOrphans(Array(selectedOrphans))
                }
                .buttonStyle(.siftSecondary)
                .disabled(isRemoving)
            }

            Button(role: .destructive) {
                pendingRemoval = selectedOrphans
                showRemovalConfirmation = true
            } label: {
                Label {
                    Text(removeSelectedLabel)
                } icon: {
                    SiftIcon.trash2.image(15)
                }
            }
            .buttonStyle(.siftPrimary)
            .disabled(selectedOrphans.isEmpty || isRemoving)
        }
    }

    private var orphanedFilesTitle: String {
        LeftoversTitle.text(
            count: appState.orphanedFiles.count,
            scanned: appState.orphanScanCompleted)
    }

    private var removeSelectedLabel: String {
        String(format: String(localized: "Remove Selected (%lld)"), Int64(selectedOrphans.count))
    }

    private var ignoreSelectedLabel: String {
        String(format: String(localized: "Ignore Selected (%lld)"), Int64(selectedOrphans.count))
    }

    /// Persist the given URLs to the ignore list (so future scans skip them)
    /// and drop them from the local selection.
    private func ignoreOrphans(_ urls: [URL]) {
        appState.ignoreOrphans(urls)
        selectedOrphans.subtract(urls)
    }

    private func orphanBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { selectedOrphans.contains(url) },
            set: { selected in
                if selected {
                    selectedOrphans.insert(url)
                } else {
                    selectedOrphans.remove(url)
                }
            }
        )
    }

    private func removeSelectedOrphans(_ batch: Set<URL>) async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }

        let urlsToRemove = batch
        var failedPaths: [String] = []
        var removedURLs: Set<URL> = []
        var needsAdminURLs: [URL] = []

        for url in urlsToRemove {
            guard OrphanSafetyPolicy.isSafeCandidate(url) else {
                failedPaths.append("\(url.path) (\(String(localized: "blocked by safety policy")))")
                continue
            }

            let outcome = await Task.detached(priority: .userInitiated) { Self.removeOrphan(url) }.value
            switch outcome {
            case .removed:
                removedURLs.insert(url)
            case .needsAdmin:
                needsAdminURLs.append(url)
            case .failed:
                failedPaths.append(url.path)
            }
        }

        if !needsAdminURLs.isEmpty {
            let adminURLs = needsAdminURLs
            let adminSucceeded = await Task.detached(priority: .userInitiated) { Self.removeWithAdminPrivileges(adminURLs) }.value
            if adminSucceeded {
                for url in needsAdminURLs {
                    if !FileManager.default.fileExists(atPath: url.path) {
                        removedURLs.insert(url)
                    } else {
                        failedPaths.append(url.path)
                    }
                }
            } else {
                failedPaths.append(contentsOf: needsAdminURLs.map(\.path))
            }
        }

        // Sweep removed rows out (per-row transitions are attached in the
        // List above); plain assignment under Reduce Motion.
        if reduceMotion {
            appState.orphanedFiles.removeAll { removedURLs.contains($0) }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                appState.orphanedFiles.removeAll { removedURLs.contains($0) }
            }
        }
        selectedOrphans.subtract(removedURLs)

        if !failedPaths.isEmpty {
            let preview = failedPaths.prefix(3).joined(separator: "\n")
            let suffix = failedPaths.count > 3 ? "\n…" : ""
            removalErrorMessage = String(
                format: String(localized: "%lld item(s) failed to delete.\n\n%@"),
                Int64(failedPaths.count),
                preview + suffix
            )
        }
    }

    private enum OrphanRemoveOutcome: Sendable {
        case removed
        case needsAdmin
        case failed
    }

    private nonisolated static func removeOrphan(_ url: URL) -> OrphanRemoveOutcome {
        guard OrphanSafetyPolicy.isSafeCandidate(url) else { return .failed }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .removed
        } catch {
            let nsError = error as NSError
            let permissionDeniedCodes = [
                NSFileReadNoPermissionError,
                NSFileWriteNoPermissionError,
                NSFileWriteUnknownError,
                257,
                513,
            ]

            guard permissionDeniedCodes.contains(nsError.code) else {
                return .failed
            }

            return .needsAdmin
        }
    }

    private func revealInFinder(_ url: URL) {
        // activateFileViewerSelecting handles sandbox-bookmarked paths and
        // missing files better than selectFile(_:inFileViewerRootedAtPath:),
        // which silently no-ops when the path is unreachable from Finder's
        // current scope. If the target itself was removed since the scan,
        // fall back to opening the enclosing directory so the user lands
        // somewhere useful instead of nothing happening.
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        let parent = url.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.path) {
            NSWorkspace.shared.open(parent)
        }
    }

    private nonisolated static func removeWithAdminPrivileges(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return true }
        guard urls.allSatisfy({ OrphanSafetyPolicy.isSafeCandidate($0) }) else { return false }

        let script = ShellQuoting.removalAppleScript(paths: urls.map(\.path))
            + " with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                return false
            }
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Row

/// Orphan row extracted to its own struct so hover state is per-row. Follows
/// the Installers table row: checkbox, 36 pt tile, name over a mono path, and
/// a hover-revealed Finder chip before the mono size.
private struct OrphanRowView: View {
    let fileURL: URL
    @Binding var isSelected: Bool
    let fileSize: Int64?
    let onReveal: () -> Void
    let onCopyPath: () -> Void
    let onIgnore: () -> Void
    let onTrash: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            // The Sift checkbox draws its label, so the name goes to accessibility only.
            Toggle(isOn: $isSelected) { EmptyView() }
                .toggleStyle(.siftCheckbox)
                .accessibilityLabel(Text(fileURL.lastPathComponent))

            Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                .resizable()
                .frame(width: 20, height: 20)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isSelected ? SiftColor.accentTint : SiftColor.control)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(fileURL.lastPathComponent)
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                Text(fileURL.path)
                    .siftStyle(.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Hover-revealed Finder shortcut; stays in the layout so the
            // trailing size never shifts sideways.
            Button {
                onReveal()
            } label: {
                HStack(spacing: 6) {
                    SiftIcon.folderOpen.image(13)
                    Text("Reveal in Finder")
                        .font(.sift(11.5))
                }
                .foregroundStyle(SiftColor.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule(style: .continuous).fill(SiftColor.track))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)

            Group {
                if let size = fileSize {
                    Text(SiftFormat.bytes(size))
                } else {
                    Text(verbatim: "…")
                }
            }
            .font(.siftMono(12.5))
            .foregroundStyle(isSelected ? SiftColor.accent : (fileSize == nil ? SiftColor.textTertiary : SiftColor.textPrimary))
            .lineLimit(1)
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .siftRowBackground(accented: isSelected, radius: 16)
        .onTapGesture { isSelected.toggle() }
        .animation(reduceMotion ? nil : SiftMotion.quick, value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Reveal in Finder") { onReveal() }
            Button("Copy Path") { onCopyPath() }
            Divider()
            Button("Always Ignore") { onIgnore() }
            Button("Move to Trash", role: .destructive) { onTrash() }
        }
    }
}
