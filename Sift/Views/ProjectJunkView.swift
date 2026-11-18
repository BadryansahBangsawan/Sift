import AppKit
import SwiftUI

/// Dependency folders and build output inside the user's project folders.
/// Only folders `ProjectJunkFinder` can prove are generated are listed; they
/// go to the Trash, and every one is checked again right before it moves.
struct ProjectJunkView: View {
    private enum ScreenState: Equatable {
        case idle
        case scanning
        case finished
        case failed(String)
    }

    private struct ProjectGroup: Identifiable {
        let project: URL
        let artifacts: [ProjectArtifact]
        var id: URL { project }
        var size: Int64 { artifacts.reduce(0) { $0 + $1.size } }
    }

    private let finder: ProjectJunkFinder
    @State private var folders: [URL] = ProjectFolders.load()
    @State private var state: ScreenState = .idle
    @State private var result: ProjectJunkScanResult?
    @State private var progress = ProjectJunkScanProgress(foldersVisited: 0, candidatesChecked: 0, candidatesTotal: 0, currentURL: nil)
    @State private var selectedIDs: Set<URL> = []
    @State private var scanTask: Task<Void, Never>?
    @State private var scanGeneration = UUID()
    @State private var isMovingToTrash = false
    @State private var showsTrashConfirmation = false
    @State private var message: ProjectJunkMessage?

    init(finder: ProjectJunkFinder = ProjectJunkFinder()) {
        self.finder = finder
    }

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            header
            foldersCard
            content
            if result?.artifacts.isEmpty == false {
                selectionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Move the selected folders to Trash?",
            isPresented: $showsTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { moveSelectedToTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(selectedIDs.count) folders totaling \(format(selectedSize)) will be moved to Trash. Sift checks each folder again first. Reinstall dependencies or rebuild to get them back.")
        }
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail), dismissButton: .default(Text("OK")))
        }
        .onDisappear {
            scanGeneration = UUID()
            scanTask?.cancel()
        }
    }

    // MARK: Header

    private var header: some View {
        SiftToolHeader(
            Text("Project junk"),
            eyebrow: Text("Cleanup"),
            subtitle: Text("Dependencies and build output Sift can prove are generated. Your source code is never listed.")
        ) {
            if state == .scanning {
                Button("Cancel", role: .cancel) { scanTask?.cancel() }
                    .buttonStyle(.siftSecondary)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button {
                    startScan()
                } label: {
                    Label(result == nil ? "Scan projects" : "Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SiftButtonStyle(kind: result == nil ? .primary : .secondary))
                .disabled(folders.isEmpty || isMovingToTrash)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private var foldersCard: some View {
        HStack(alignment: .center, spacing: 10) {
            SiftIconTile(icon: .folder, tone: .neutral, size: 30)
            if folders.isEmpty {
                Text("No project folders yet")
                    .siftStyle(.label)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(folders, id: \.self) { folder in
                            folderChip(folder)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Button {
                addFolders()
            } label: {
                Label("Add folder…", systemImage: "plus")
            }
            .buttonStyle(.sift(.secondary, compact: true))
            .disabled(state == .scanning || isMovingToTrash)
        }
        .siftSurface(.card)
    }

    private func folderChip(_ folder: URL) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: abbreviated(folder))
                .font(.siftMono(11.5))
                .foregroundStyle(SiftColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder.path)
            Button {
                removeFolder(folder)
            } label: {
                SiftIcon.x.image(10)
                    .foregroundStyle(SiftColor.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(state == .scanning || isMovingToTrash)
            .accessibilityLabel("Remove \(folder.lastPathComponent)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle:
            if folders.isEmpty {
                SiftEmptyState(
                    icon: .folder,
                    title: Text("Choose your project folders"),
                    message: Text("Add the folders where you keep code. Sift looks for node_modules, .venv, target, .build and similar folders inside them.")
                ) {
                    Button("Add folder…") { addFolders() }
                        .buttonStyle(.siftSecondary)
                }
            } else {
                SiftEmptyState(
                    icon: .package,
                    title: Text("Find dependencies and build output"),
                    message: Text("A folder is listed only when its project file sits next to it, its contents look generated, and git ignores it. Folders move to the Trash."),
                    footnote: Text("Nothing changes during a scan.")
                ) {
                    Button("Scan projects") { startScan() }
                        .buttonStyle(.siftSecondary)
                }
            }
        case .scanning:
            SiftScanningCard(
                title: Text(progress.candidatesTotal == 0 ? "Looking through project folders" : "Checking each folder"),
                detail: Text(verbatim: progress.currentURL.map(abbreviated) ?? ""),
                fraction: progress.candidatesTotal > 0 ? Double(progress.candidatesChecked) / Double(progress.candidatesTotal) : nil,
                stop: { scanTask?.cancel() }
            ) {
                SiftCountPill(String(localized: "\(progress.foldersVisited.formatted()) folders searched"))
            }
        case .failed(let error):
            SiftEmptyState(icon: .triangleAlert, tone: .warning, title: Text("The scan stopped"), message: Text(verbatim: error)) {
                Button("Scan projects") { startScan() }
                    .buttonStyle(.siftSecondary)
            }
        case .finished:
            if let result, result.artifacts.isEmpty {
                SiftEmptyState(
                    icon: .shieldCheck,
                    tone: .success,
                    title: Text("No project junk found"),
                    message: Text("None of your project folders has dependencies or build output Sift can prove are safe to remove.")
                ) {
                    EmptyView()
                }
                if !result.skipped.isEmpty {
                    skippedCard(result.skipped)
                }
            } else if let result {
                resultContent(result)
            }
        }
    }

    private func resultContent(_ result: ProjectJunkScanResult) -> some View {
        ScrollView {
            LazyVStack(spacing: SiftSpacing.gutter) {
                ForEach(groups(result)) { group in
                    projectCard(group)
                }
                if !result.skipped.isEmpty {
                    skippedCard(result.skipped)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectCard(_ group: ProjectGroup) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                SiftIconTile(icon: .folder, tone: .accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: group.project.lastPathComponent)
                        .siftStyle(.cardTitle)
                        .lineLimit(1)
                    Text(verbatim: abbreviated(group.project))
                        .siftStyle(.monoSmall)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(format(group.size))
                    .font(.siftMono(12.5))
                    .foregroundStyle(SiftColor.textSecondary)
                Button(group.artifacts.allSatisfy { selectedIDs.contains($0.id) } ? "Deselect all" : "Select all") {
                    toggle(group)
                }
                .buttonStyle(.sift(.secondary, compact: true))
                .disabled(isMovingToTrash)
            }
            VStack(spacing: 2) {
                ForEach(group.artifacts) { artifact in
                    artifactRow(artifact)
                }
            }
        }
        .siftSurface(.card)
    }

    private func artifactRow(_ artifact: ProjectArtifact) -> some View {
        HStack(spacing: 14) {
            Toggle("", isOn: selection(for: artifact.id))
                .labelsHidden()
                .toggleStyle(.siftCheckbox)
                .frame(width: 20, alignment: .leading)
                .disabled(isMovingToTrash)
                .accessibilityLabel("Select \(artifact.kind) in \(artifact.project.lastPathComponent)")
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: artifact.kind)
                    .font(.siftMono(13))
                    .foregroundStyle(SiftColor.textPrimary)
                Text(verbatim: evidenceLine(artifact))
                    .siftStyle(.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if let modifiedAt = artifact.modifiedAt {
                Text(modifiedAt, style: .date)
                    .siftStyle(.label)
            }
            Text(format(artifact.size))
                .font(.siftDisplay(16, weight: 600).monospacedDigit())
                .foregroundStyle(selectedIDs.contains(artifact.id) ? SiftColor.accent : SiftColor.textPrimary)
                .frame(minWidth: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
            } label: {
                SiftIcon.folderOpen.image(13)
                    .foregroundStyle(SiftColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(SiftColor.track))
            }
            .buttonStyle(.plain)
            .help("Reveal in Finder")
            .accessibilityLabel("Reveal \(artifact.kind) in Finder")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .siftRowBackground(accented: selectedIDs.contains(artifact.id), radius: 14)
    }

    private func skippedCard(_ skipped: [ProjectArtifactSkip]) -> some View {
        DisclosureGroup {
            VStack(spacing: 2) {
                ForEach(skipped) { item in
                    HStack(spacing: 12) {
                        SiftIcon.shieldCheck.image(14)
                            .foregroundStyle(SiftColor.textTertiary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: abbreviated(item.url))
                                .font(.siftMono(11))
                                .foregroundStyle(SiftColor.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(verbatim: item.reason.message)
                                .siftStyle(.caption)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .siftRowBackground()
                }
            }
            .padding(.top, 14)
        } label: {
            HStack(spacing: 10) {
                SiftIconTile(icon: .shieldCheck, tone: .neutral, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Left alone")
                        .siftStyle(.cardTitle)
                    Text("\(skipped.count) folders have a familiar name but Sift couldn't prove they are generated")
                        .siftStyle(.label)
                }
            }
        }
        .disclosureGroupStyle(.sift)
        .siftSurface(.card)
    }

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
                Text(selectedIDs.isEmpty ? "Select the folders you want to remove" : "\(format(selectedSize)) will move to Trash")
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
                    ProgressView().controlSize(.small).frame(minWidth: 100)
                } else {
                    Label("Move to Trash", systemImage: "trash")
                }
            }
            .buttonStyle(.siftPrimary)
            .disabled(selectedIDs.isEmpty || isMovingToTrash || state == .scanning)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .frame(height: 64)
        .background(Capsule(style: .continuous).fill(SiftColor.control))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
    }

    // MARK: Actions

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose project folders")
        panel.prompt = String(localized: "Add")
        panel.message = String(localized: "Sift searches these folders for dependencies and build output.")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        folders = ProjectFolders.normalized(folders + panel.urls)
        ProjectFolders.save(folders)
        result = nil
        selectedIDs.removeAll()
        state = .idle
    }

    private func removeFolder(_ folder: URL) {
        folders.removeAll { $0 == folder }
        ProjectFolders.save(folders)
        result = nil
        selectedIDs.removeAll()
        state = .idle
    }

    private func startScan() {
        guard !folders.isEmpty, !isMovingToTrash else { return }
        scanTask?.cancel()
        let generation = UUID()
        scanGeneration = generation
        let roots = folders
        result = nil
        selectedIDs.removeAll()
        progress = ProjectJunkScanProgress(foldersVisited: 0, candidatesChecked: 0, candidatesTotal: 0, currentURL: roots.first)
        state = .scanning
        let finder = finder
        scanTask = Task { @MainActor in
            do {
                let scan = try await Task.detached(priority: .userInitiated) {
                    try await finder.scan(roots: roots) { update in
                        await MainActor.run {
                            guard scanGeneration == generation else { return }
                            progress = update
                        }
                    }
                }.value
                guard scanGeneration == generation, !Task.isCancelled else { return }
                result = scan
                // The owner's choice: everything Sift can prove is junk starts selected.
                selectedIDs = Set(scan.artifacts.map(\.id))
                state = .finished
            } catch is CancellationError {
                if scanGeneration == generation { state = .idle }
            } catch {
                if scanGeneration == generation { state = .failed(error.localizedDescription) }
            }
            if scanGeneration == generation { scanTask = nil }
        }
    }

    private func moveSelectedToTrash() {
        guard let current = result, !selectedIDs.isEmpty else { return }
        let chosen = current.artifacts.filter { selectedIDs.contains($0.id) }
        let roots = current.roots
        let finder = finder
        isMovingToTrash = true
        Task { @MainActor in
            let report = await Task.detached(priority: .userInitiated) {
                finder.moveToTrash(chosen, roots: roots)
            }.value
            isMovingToTrash = false
            let movedIDs = Set(report.moved.map(\.id))
            result = ProjectJunkScanResult(
                roots: current.roots,
                artifacts: current.artifacts.filter { !movedIDs.contains($0.id) },
                skipped: current.skipped
            )
            selectedIDs.subtract(movedIDs)
            let movedSize = format(report.moved.reduce(0) { $0 + $1.size })
            if report.failures.isEmpty {
                message = ProjectJunkMessage(
                    title: String(localized: "Moved to Trash"),
                    detail: String(localized: "\(report.moved.count) folders totaling \(movedSize) are in the Trash. Empty the Trash to free the space.")
                )
            } else {
                let lines = report.failures.map { "\(abbreviated($0.url)): \($0.message)" }
                message = ProjectJunkMessage(
                    title: report.moved.isEmpty ? String(localized: "Nothing was moved") : String(localized: "Some folders were not moved"),
                    detail: lines.joined(separator: "\n")
                )
            }
        }
    }

    // MARK: Helpers

    private func groups(_ result: ProjectJunkScanResult) -> [ProjectGroup] {
        Dictionary(grouping: result.artifacts, by: \.project)
            .map { ProjectGroup(project: $0.key, artifacts: $0.value.sorted { $0.size > $1.size }) }
            .sorted { $0.size > $1.size }
    }

    private func toggle(_ group: ProjectGroup) {
        let ids = Set(group.artifacts.map(\.id))
        if ids.isSubset(of: selectedIDs) { selectedIDs.subtract(ids) } else { selectedIDs.formUnion(ids) }
    }

    private func selection(for id: URL) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { isOn in if isOn { selectedIDs.insert(id) } else { selectedIDs.remove(id) } }
        )
    }

    private var selectedSize: Int64 {
        (result?.artifacts ?? []).filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private func evidenceLine(_ artifact: ProjectArtifact) -> String {
        let git = artifact.git == .ignored
            ? String(localized: "ignored by git")
            : String(localized: "no git repository")
        return (artifact.evidence + [git]).joined(separator: " · ")
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct ProjectJunkMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}
