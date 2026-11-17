import AppKit
import SwiftUI

struct DuplicateFinderView: View {
    private enum ScreenState: Equatable {
        case idle
        case scanning
        case finished
        case failed(String)
    }

    private let finder: DuplicateFinder
    @State private var state: ScreenState = .idle
    @State private var result: DuplicateScanResult?
    @State private var selectedFolder: URL?
    @State private var progress = DuplicateScanProgress(
        phase: .discovering,
        filesInspected: 0,
        filesToHash: 0,
        filesHashed: 0,
        bytesHashed: 0,
        currentURL: nil
    )
    @State private var selectedIDs: Set<URL> = []
    @State private var expandedGroupIDs: Set<String> = []
    @State private var scanGeneration = UUID()
    @State private var scanTask: Task<Void, Never>?
    @State private var trashTask: Task<Void, Never>?
    @State private var isMovingToTrash = false
    @State private var showsTrashConfirmation = false
    @State private var actionMessage: ActionMessage?

    init(finder: DuplicateFinder = DuplicateFinder()) {
        self.finder = finder
    }

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            header
            content
            if result?.groups.isEmpty == false {
                selectionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Move selected duplicates to Trash?",
            isPresented: $showsTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                moveSelectedToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedIDs.count) files totaling \(format(selectedSize)) will be moved to Trash. The protected copy in every group stays in place.")
        }
        .alert(item: $actionMessage) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("OK"))
            )
        }
        .onDisappear {
            scanGeneration = UUID()
            scanTask?.cancel()
            trashTask?.cancel()
        }
    }

    private var header: some View {
        SiftToolHeader(
            Text("Duplicate Finder"),
            eyebrow: Text("Tools"),
            subtitle: Text(verbatim: headerSubtitle)
        ) {
            if state == .scanning {
                Button("Cancel", role: .cancel) {
                    scanTask?.cancel()
                }
                .buttonStyle(.siftSecondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Stops scanning without changing any files")
            } else {
                Button {
                    chooseFolder()
                } label: {
                    Label(result == nil ? "Choose Folder" : "Scan Another Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(SiftButtonStyle(kind: result == nil ? .primary : .secondary))
                .disabled(isMovingToTrash)
                .accessibilityHint("Opens a folder picker")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            idleState
        case .scanning:
            scanningState
        case .failed(let message):
            failureState(message)
        case .finished:
            if let result, result.groups.isEmpty {
                emptyResult(result)
            } else if let result {
                resultContent(result)
            } else {
                idleState
            }
        }
    }

    private var idleState: some View {
        SiftEmptyState(
            icon: .copy,
            title: Text("Find copies that are exactly the same"),
            message: Text("Choose a folder. Sift compares file sizes and SHA-256 content hashes. Nothing is selected or removed automatically.")
        ) {
            Button {
                chooseFolder()
            } label: {
                Label("Choose a Folder", systemImage: "folder")
            }
            .buttonStyle(.siftSecondary)
            .disabled(isMovingToTrash)
        }
    }

    private var scanningState: some View {
        SiftScanningCard(
            title: Text(progress.phase == .discovering ? "Looking through files" : "Verifying possible matches"),
            detail: Text(verbatim: progress.currentURL?.path ?? ""),
            fraction: progress.fractionCompleted
        ) {
            SiftCountPill(progressSummary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(progressSummary)
    }

    private func failureState(_ message: String) -> some View {
        SiftEmptyState(
            icon: .triangleAlert,
            tone: .warning,
            title: Text("Scan could not finish"),
            message: Text(message)
        ) {
            if let folder = selectedFolder {
                Button("Try Again") { startScan(folder) }
                    .buttonStyle(.siftSecondary)
                    .disabled(isMovingToTrash)
            }
            Button("Choose Another Folder") { chooseFolder() }
                .buttonStyle(.siftSecondary)
                .disabled(isMovingToTrash)
        }
    }

    private func emptyResult(_ result: DuplicateScanResult) -> some View {
        SiftEmptyState(
            icon: .check,
            tone: .success,
            title: Text("No exact duplicates found"),
            message: Text("Inspected \(result.filesInspected.formatted()) files in \(result.folder.lastPathComponent). \(skippedSummary(result.skippedFiles))")
        ) {
            Button("Scan Again") { startScan(result.folder) }
                .buttonStyle(.siftSecondary)
                .disabled(isMovingToTrash)
        }
    }

    private func resultContent(_ result: DuplicateScanResult) -> some View {
        VStack(spacing: SiftSpacing.gutter) {
            summaryCard(result)
            ScrollView {
                LazyVStack(spacing: SiftSpacing.gutter) {
                    ForEach(result.groups) { group in
                        groupCard(group)
                    }
                    if !result.skippedFiles.isEmpty {
                        skippedCard(result.skippedFiles)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func summaryCard(_ result: DuplicateScanResult) -> some View {
        HStack(spacing: 0) {
            summaryMetric(value: result.groups.count.formatted(), label: "Duplicate groups", icon: .copy, tone: .neutral)
            metricDivider
            summaryMetric(value: result.duplicateFileCount.formatted(), label: "Matching files", icon: .file, tone: .neutral)
            metricDivider
            summaryMetric(value: format(result.reclaimableSize), label: "Available to review", icon: .hardDrive, tone: .accent)
            Spacer(minLength: 10)
            Button("Rescan") { startScan(result.folder) }
                .buttonStyle(.siftSecondary)
                .disabled(isMovingToTrash)
        }
        .siftSurface(.card)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SiftColor.stroke)
            .frame(width: 1, height: 44)
            .padding(.horizontal, 20)
    }

    private func summaryMetric(value: String, label: LocalizedStringKey, icon: SiftIcon, tone: SiftTone) -> some View {
        HStack(spacing: 12) {
            SiftIconTile(icon: icon, tone: tone)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .siftStyle(.metricSmall)
                    .foregroundStyle(tone == .accent ? SiftColor.accent : SiftColor.textPrimary)
                    .lineLimit(1)
                Text(label)
                    .siftStyle(.label)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SiftIconTile(icon: .copy, tone: .accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.keeper.url.lastPathComponent)
                        .siftStyle(.cardTitle)
                        .lineLimit(1)
                    Text("\(group.files.count) exact copies · \(format(group.fileSize)) each")
                        .siftStyle(.monoSmall)
                }
                Spacer()
                SiftStatusPill(Text(verbatim: String(localized: "\(format(group.reclaimableSize)) reviewable")), tone: .accent)
                Button(groupCandidatesSelected(group) ? "Clear" : "Select copies") {
                    toggleGroupSelection(group)
                }
                .buttonStyle(.sift(.secondary, compact: true))
                .disabled(isMovingToTrash)
                Button {
                    toggleExpanded(group)
                } label: {
                    SiftIcon.chevronDown.image(14)
                        .foregroundStyle(SiftColor.textSecondary)
                        .rotationEffect(.degrees(expandedGroupIDs.contains(group.id) ? 180 : 0))
                }
                .buttonStyle(.siftQuiet)
                .accessibilityLabel(expandedGroupIDs.contains(group.id) ? "Collapse duplicate group" : "Expand duplicate group")
            }

            if expandedGroupIDs.contains(group.id) {
                VStack(spacing: 2) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                        fileRow(file, keeper: index == 0)
                    }
                }
                .padding(.top, 14)
                .transition(.opacity)
            }
        }
        .siftSurface(.card)
    }

    /// The Installers row: checkbox, icon tile, name over a mono path, date, reveal.
    private func fileRow(_ file: DuplicateFile, keeper: Bool) -> some View {
        HStack(spacing: 14) {
            if keeper {
                SiftIcon.shieldCheck.image(17)
                    .foregroundStyle(SiftColor.success)
                    .frame(width: 20)
                    .accessibilityLabel("Protected copy")
            } else {
                Toggle("", isOn: selectionBinding(for: file.url))
                    .labelsHidden()
                    .toggleStyle(.siftCheckbox)
                    .frame(width: 20, alignment: .leading)
                    .disabled(isMovingToTrash)
                    .allowsHitTesting(!isMovingToTrash)
                    .accessibilityLabel("Select \(file.url.lastPathComponent)")
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(SiftColor.control))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(file.url.lastPathComponent)
                        .font(.sift(13.5, weight: keeper ? 500 : 400))
                        .foregroundStyle(SiftColor.textPrimary)
                        .lineLimit(1)
                    if keeper {
                        SiftStatusPill(Text("Keep"), tone: .success)
                    }
                }
                Text(file.url.deletingLastPathComponent().path)
                    .siftStyle(.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let modifiedAt = file.modifiedAt {
                Text(modifiedAt, style: .date)
                    .siftStyle(.label)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                SiftIcon.folderOpen.image(13)
                    .foregroundStyle(SiftColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(SiftColor.track))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reveal \(file.url.lastPathComponent) in Finder")
            .help("Reveal in Finder")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .siftRowBackground(accented: selectedIDs.contains(file.url), radius: 16)
        .accessibilityElement(children: .contain)
    }

    private func skippedCard(_ skippedFiles: [DuplicateSkippedFile]) -> some View {
        DisclosureGroup {
            VStack(spacing: 2) {
                ForEach(skippedFiles) { file in
                    HStack(spacing: 12) {
                        SiftIcon.triangleAlert.image(14)
                            .foregroundStyle(SiftColor.warning)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.url.path)
                                .font(.siftMono(11))
                                .foregroundStyle(SiftColor.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(file.detail.map { "\(file.reason.label): \($0)" } ?? file.reason.label)
                                .siftStyle(.caption)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        } label: {
                            SiftIcon.folderOpen.image(13)
                                .foregroundStyle(SiftColor.textTertiary)
                        }
                        .buttonStyle(.siftQuiet)
                        .accessibilityLabel("Reveal skipped item in Finder")
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .siftRowBackground()
                }
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 10) {
                SiftIconTile(icon: .triangleAlert, tone: .warning, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skipped items")
                        .siftStyle(.cardTitle)
                    Text("\(skippedFiles.count) unsafe or unavailable items were not scanned")
                        .siftStyle(.label)
                }
            }
        }
        .disclosureGroupStyle(.sift)
        .siftSurface(.card)
    }

    /// The Installers action bar, pinned below the list.
    private var selectionBar: some View {
        HStack(spacing: 14) {
            SiftIcon.trash2.image(14)
                .foregroundStyle(selectedIDs.isEmpty ? SiftColor.textTertiary : SiftColor.onAccent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(selectedIDs.isEmpty ? SiftColor.track : SiftColor.accent))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedIDs.isEmpty ? "Nothing selected" : "\(selectedIDs.count) selected")
                    .font(.sift(13.5, weight: 500).monospacedDigit())
                    .foregroundStyle(SiftColor.textPrimary)
                Text(selectedIDs.isEmpty ? "Select the extra copies you want to review" : "\(format(selectedSize)) will move to Trash")
                    .siftStyle(.label)
            }
            Spacer()
            if !selectedIDs.isEmpty {
                Button("Clear Selection") { selectedIDs.removeAll() }
                    .buttonStyle(.sift(.quiet))
                    .disabled(isMovingToTrash)
            }
            Button {
                showsTrashConfirmation = true
            } label: {
                if isMovingToTrash {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 100)
                } else {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
            .buttonStyle(.siftPrimary)
            .disabled(selectedIDs.isEmpty || isMovingToTrash || state == .scanning)
            .accessibilityHint("Shows a confirmation before moving the selected copies")
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 64)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
    }

    private var headerSubtitle: String {
        if state == .scanning, let current = progress.currentURL {
            return current.deletingLastPathComponent().path
        }
        return selectedFolder?.path ?? String(localized: "Exact-match cleanup with a protected copy in every group")
    }

    private var progressSummary: String {
        switch progress.phase {
        case .discovering:
            return String(localized: "\(progress.filesInspected.formatted()) files inspected")
        case .hashing:
            return String(localized: "\(progress.filesHashed.formatted()) of \(progress.filesToHash.formatted()) candidates · \(format(progress.bytesHashed)) verified")
        }
    }

    private var selectedSize: Int64 {
        guard let result else { return 0 }
        return result.groups
            .flatMap(\.files)
            .filter { selectedIDs.contains($0.url) }
            .reduce(0) { $0 + $1.size }
    }

    private func selectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(url) },
            set: { selected in
                if selected {
                    selectedIDs.insert(url)
                } else {
                    selectedIDs.remove(url)
                }
            }
        )
    }

    private func groupCandidatesSelected(_ group: DuplicateGroup) -> Bool {
        group.files.dropFirst().allSatisfy { selectedIDs.contains($0.url) }
    }

    private func toggleGroupSelection(_ group: DuplicateGroup) {
        let candidateIDs = Set(group.files.dropFirst().map(\.url))
        if candidateIDs.isSubset(of: selectedIDs) {
            selectedIDs.subtract(candidateIDs)
        } else {
            selectedIDs.formUnion(candidateIDs)
        }
    }

    private func toggleExpanded(_ group: DuplicateGroup) {
        withAnimation(SiftMotion.snappy) {
            if expandedGroupIDs.contains(group.id) {
                expandedGroupIDs.remove(group.id)
            } else {
                expandedGroupIDs.insert(group.id)
            }
        }
    }

    private func chooseFolder() {
        guard !isMovingToTrash else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a folder to check for duplicate files")
        panel.prompt = String(localized: "Scan Folder")
        panel.message = String(localized: "Sift reads the selected folder and does not change anything during a scan.")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let folder = panel.url {
            startScan(folder)
        }
    }

    private func startScan(_ folder: URL) {
        guard !isMovingToTrash else { return }
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        selectedFolder = folder
        selectedIDs.removeAll()
        expandedGroupIDs.removeAll()
        result = nil
        progress = DuplicateScanProgress(
            phase: .discovering,
            filesInspected: 0,
            filesToHash: 0,
            filesHashed: 0,
            bytesHashed: 0,
            currentURL: folder
        )
        state = .scanning
        scanTask = Task { @MainActor in
            let usesScopedAccess = folder.startAccessingSecurityScopedResource()
            defer {
                if usesScopedAccess {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let scanResult = try await finder.scan(folder: folder) { update in
                    await MainActor.run {
                        guard scanGeneration == generation else { return }
                        progress = update
                    }
                }
                try Task.checkCancellation()
                guard scanGeneration == generation else { return }
                result = scanResult
                expandedGroupIDs = Set(scanResult.groups.prefix(3).map(\.id))
                state = .finished
            } catch is CancellationError {
                guard scanGeneration == generation else { return }
                state = .idle
            } catch {
                guard scanGeneration == generation else { return }
                state = .failed(error.localizedDescription)
            }
            if scanGeneration == generation {
                scanTask = nil
            }
        }
    }

    private func moveSelectedToTrash() {
        guard let currentResult = result, !selectedIDs.isEmpty else { return }
        let generation = scanGeneration
        let folder = currentResult.folder
        let selectionSnapshot = selectedIDs
        isMovingToTrash = true
        trashTask = Task { @MainActor in
            let usesScopedAccess = currentResult.folder.startAccessingSecurityScopedResource()
            defer {
                if usesScopedAccess {
                    currentResult.folder.stopAccessingSecurityScopedResource()
                }
                if scanGeneration == generation {
                    isMovingToTrash = false
                    trashTask = nil
                }
            }
            var movedFiles: [DuplicateFile] = []
            var failures: [String] = []
            for group in currentResult.groups {
                if Task.isCancelled { return }
                let groupSelection = selectionSnapshot.filter { group.contains($0) }
                guard !groupSelection.isEmpty else { continue }
                do {
                    let report = try await finder.moveToTrash(group: group, selectedIDs: groupSelection)
                    movedFiles.append(contentsOf: report.trashedFiles)
                    failures.append(contentsOf: report.failures.map { "\($0.url.lastPathComponent): \($0.message)" })
                } catch {
                    failures.append(error.localizedDescription)
                }
            }
            guard scanGeneration == generation,
                  selectedFolder == folder,
                  result?.folder == folder,
                  !Task.isCancelled else { return }
            applyTrashResult(movedFiles)
            if failures.isEmpty {
                actionMessage = ActionMessage(
                    title: String(localized: "Moved to Trash"),
                    detail: String(localized: "\(movedFiles.count) files totaling \(format(movedFiles.reduce(0) { $0 + $1.size })) were moved. Every protected copy remains in place.")
                )
            } else {
                actionMessage = ActionMessage(
                    title: movedFiles.isEmpty ? String(localized: "Nothing was moved") : String(localized: "Some files were not moved"),
                    detail: failures.joined(separator: "\n")
                )
            }
        }
    }

    private func applyTrashResult(_ movedFiles: [DuplicateFile]) {
        guard let currentResult = result else { return }
        let movedIDs = Set(movedFiles.map(\.url))
        let remainingGroups = currentResult.groups.compactMap { group -> DuplicateGroup? in
            let remaining = group.files.filter { !movedIDs.contains($0.url) }
            guard remaining.count > 1 else { return nil }
            return DuplicateGroup(digest: group.digest, files: remaining)
        }
        result = DuplicateScanResult(
            folder: currentResult.folder,
            groups: remainingGroups,
            skippedFiles: currentResult.skippedFiles,
            filesInspected: currentResult.filesInspected,
            bytesHashed: currentResult.bytesHashed
        )
        selectedIDs.subtract(movedIDs)
        expandedGroupIDs.formIntersection(Set(remainingGroups.map(\.id)))
    }

    private func skippedSummary(_ skippedFiles: [DuplicateSkippedFile]) -> String {
        skippedFiles.isEmpty
            ? String(localized: "Every eligible file was checked.")
            : String(localized: "\(skippedFiles.count) unsafe or unavailable items were skipped.")
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct ActionMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}
