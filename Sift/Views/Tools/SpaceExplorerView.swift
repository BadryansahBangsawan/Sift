import AppKit
import SwiftUI

@MainActor
final class SpaceExplorerViewModel: ObservableObject {
    enum Phase {
        case idle
        case scanning
        case loaded
        case failed(String)
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var result: StorageScanResult?
    @Published private(set) var progress: StorageScanProgress?
    @Published private(set) var path: [URL] = []

    private let explorer: StorageExplorer
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()

    init(explorer: StorageExplorer = StorageExplorer()) {
        self.explorer = explorer
    }

    var currentURL: URL? { path.last }
    var canGoBack: Bool { path.count > 1 && !isScanning }
    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a folder to inspect")
        panel.message = String(localized: "Sift measures allocated disk space without changing files.")
        panel.prompt = String(localized: "Inspect")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = [url.standardizedFileURL]
        startScan(at: url)
    }

    func open(_ entry: StorageEntry) {
        guard entry.isDirectory, !isScanning else { return }
        let url = entry.url.standardizedFileURL
        path.append(url)
        startScan(at: url)
    }

    func goBack() {
        guard canGoBack else { return }
        path.removeLast()
        guard let url = path.last else { return }
        startScan(at: url)
    }

    func rescan() {
        guard let url = currentURL else { return }
        startScan(at: url)
    }

    func cancel() {
        guard isScanning else { return }
        scanTask?.cancel()
        phase = .cancelled
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func startScan(at url: URL) {
        scanTask?.cancel()
        let id = UUID()
        scanID = id
        result = nil
        progress = StorageScanProgress(
            rootURL: url,
            currentURL: url,
            allocatedSize: 0,
            scannedItemCount: 0,
            inaccessibleCount: 0,
            skippedCount: 0
        )
        phase = .scanning

        scanTask = Task { [self, explorer] in
            do {
                let result = try await explorer.scan(at: url) { progress in
                    Task { @MainActor [self] in
                        guard self.scanID == id, self.isScanning else { return }
                        self.progress = progress
                    }
                }
                guard self.scanID == id else { return }
                self.result = result
                self.progress = nil
                self.phase = .loaded
            } catch is CancellationError {
                guard self.scanID == id, self.isScanning else { return }
                self.phase = .cancelled
            } catch {
                guard self.scanID == id else { return }
                self.progress = nil
                self.phase = .failed(error.localizedDescription)
            }
        }
    }
}

struct SpaceExplorerView: View {
    @StateObject private var model = SpaceExplorerViewModel()

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            header

            if let currentURL = model.currentURL {
                locationBar(currentURL)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Space explorer")
        .onDisappear {
            model.cancel()
        }
    }

    private var header: some View {
        SiftToolHeader(
            Text("Space explorer"),
            eyebrow: Text("Tools"),
            subtitle: Text("Inspect a folder by allocated disk space. Your files are never changed.")
        ) {
            Button {
                model.chooseFolder()
            } label: {
                Label(model.currentURL == nil ? "Choose Folder" : "Choose Another Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.siftPrimary)
            .disabled(model.isScanning)
        }
    }

    private func locationBar(_ url: URL) -> some View {
        SiftPathBar(path: url.path) {
            Button {
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SiftColor.textSecondary)
            }
            .buttonStyle(.siftQuiet)
            .disabled(!model.canGoBack)
            .help("Back")
            .accessibilityLabel(Text("Back"))
        } actions: {
            Button {
                model.reveal(url)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .buttonStyle(.sift(.secondary, compact: true))

            Button {
                model.rescan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.sift(.secondary, compact: true))
            .disabled(model.isScanning)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            idleState
        case .scanning:
            scanningState
        case .loaded:
            if let result = model.result {
                resultView(result)
            } else {
                idleState
            }
        case .failed(let message):
            messageState(
                title: "Folder could not be inspected",
                message: message,
                icon: .triangleAlert,
                tone: .warning
            )
        case .cancelled:
            messageState(
                title: "Scan stopped",
                message: String(localized: "No files were changed. Rescan this folder when you are ready."),
                icon: .info,
                tone: .neutral
            )
        }
    }

    private var idleState: some View {
        SiftEmptyState(
            icon: .chartPie,
            title: Text("Choose where to look"),
            message: Text("Select any folder to see which files and subfolders occupy the most disk space."),
            footnote: Text("Symbolic links and cloud-only items are excluded.")
        )
    }

    private var scanningState: some View {
        SiftScanningCard(
            title: Text("Measuring allocated space"),
            detail: Text(verbatim: model.progress?.currentURL.lastPathComponent ?? String(localized: "Preparing scan")),
            stop: { model.cancel() }
        ) {
            SiftCountPill(String(localized: "\(model.progress?.scannedItemCount ?? 0) items"))
            SiftCountPill(Self.format(model.progress?.allocatedSize ?? 0))
            if let progress = model.progress, progress.skippedCount > 0 {
                SiftCountPill(String(localized: "\(progress.skippedCount) skipped"), tone: .warning)
            }
            if let progress = model.progress, progress.inaccessibleCount > 0 {
                SiftCountPill(String(localized: "\(progress.inaccessibleCount) inaccessible"), tone: .warning)
            }
        }
    }

    private func resultView(_ result: StorageScanResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
                summaryCard(result)

                if result.entries.isEmpty {
                    HStack(spacing: 12) {
                        SiftIconTile(icon: .folder)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No measurable items")
                                .siftStyle(.bodyStrong)
                            Text("This folder is empty or its contents were excluded from the scan.")
                                .siftStyle(.label)
                        }
                        Spacer(minLength: 0)
                    }
                    .siftSurface(.card)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        SiftCardHeader(Text("Largest items"))
                        LazyVStack(spacing: 2) {
                            ForEach(Array(result.entries.enumerated()), id: \.element.id) { index, entry in
                                StorageEntryRow(
                                    entry: entry,
                                    totalSize: result.totalAllocatedSize,
                                    emphasized: index == 0,
                                    onOpen: { model.open(entry) },
                                    onReveal: { model.reveal(entry.url) }
                                )
                            }
                        }
                    }
                    .siftSurface(.card)
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func summaryCard(_ result: StorageScanResult) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                SiftStat(Self.format(result.totalAllocatedSize), label: Text("allocated in this folder"))
                HStack(spacing: 8) {
                    SiftCountPill(StorageEntryRow.fileCountLabel(result.fileCount))
                    SiftCountPill(StorageEntryRow.folderCountLabel(result.directoryCount))
                    SiftCountPill(String(localized: "\(result.skippedCount) skipped · \(result.inaccessibleCount) inaccessible"))
                }
            }

            Spacer()

            if result.isPartial {
                SiftStatusPill(Text("Partial result"), tone: .warning)
            }
        }
        .siftSurface(.card)
    }

    private func messageState(title: LocalizedStringKey, message: String, icon: SiftIcon, tone: SiftTone) -> some View {
        SiftEmptyState(icon: icon, tone: tone, title: Text(title), message: Text(message)) {
            Button("Rescan") {
                model.rescan()
            }
            .buttonStyle(.siftSecondary)
        }
    }

    private static func format(_ bytes: Int64) -> String {
        SiftFormat.bytes(bytes)
    }
}

/// A "Where it sits" row: icon tile, name and counts, share bar, size, chevron.
private struct StorageEntryRow: View {
    let entry: StorageEntry
    let totalSize: Int64
    let emphasized: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if entry.isDirectory {
                    Button(action: onOpen) {
                        entryContent
                    }
                    .buttonStyle(.plain)
                } else {
                    entryContent
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: onReveal) {
                SiftIcon.folderOpen.image(14)
                    .foregroundStyle(SiftColor.textTertiary)
            }
            .buttonStyle(.siftQuiet)
            .help("Show in Finder")
            .accessibilityLabel("Show \(entry.name) in Finder")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .siftRowBackground()
        .contextMenu {
            if entry.isDirectory {
                Button("Open Folder", action: onOpen)
            }
            Button("Show in Finder", action: onReveal)
        }
    }

    private var entryContent: some View {
        HStack(spacing: 14) {
            SiftIconTile(
                icon: entry.isDirectory ? .folder : (entry.isPackage ? .package : .file),
                tone: emphasized ? .accent : .neutral
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .siftStyle(.bodyStrong)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.isPartial {
                        SiftIcon.triangleAlert.image(11)
                            .foregroundStyle(SiftColor.warning)
                            .help("Some contents were skipped or inaccessible")
                    }
                }

                HStack(spacing: 8) {
                    Text(detailText)
                    if entry.skippedCount > 0 {
                        Text("\(entry.skippedCount) skipped")
                            .foregroundStyle(SiftColor.warning)
                    }
                    if entry.inaccessibleCount > 0 {
                        Text("\(entry.inaccessibleCount) inaccessible")
                            .foregroundStyle(SiftColor.warning)
                    }
                }
                .font(.siftMono(10.5))
                .foregroundStyle(SiftColor.textTertiary)
                .lineLimit(1)
            }
            .frame(width: 250, alignment: .leading)

            StorageUsageBar(value: entry.allocatedSize, total: totalSize, emphasized: emphasized)

            Text(Self.format(entry.allocatedSize))
                .siftStyle(.rowValue)
                .foregroundStyle(emphasized ? SiftColor.accent : SiftColor.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 76, alignment: .trailing)

            SiftIcon.chevronRight.image(16)
                .foregroundStyle(emphasized ? SiftColor.accent : SiftColor.faint)
                .opacity(entry.isDirectory ? 1 : 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(Self.format(entry.allocatedSize))")
        .accessibilityHint(entry.isDirectory ? "Open folder" : (entry.isPackage ? "Package" : "File"))
    }

    private var detailText: String {
        if entry.isPackage {
            return String(localized: "Package · \(Self.fileCountLabel(entry.fileCount))")
        }
        if entry.isDirectory {
            let childFolderCount = max(0, entry.directoryCount - 1)
            return "\(Self.fileCountLabel(entry.fileCount)) · \(Self.folderCountLabel(childFolderCount))"
        }
        return String(localized: "File")
    }

    static func fileCountLabel(_ count: Int) -> String {
        String(localized: "\(count) files")
    }

    static func folderCountLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "1 folder") : String(localized: "\(count) folders")
    }

    private static func format(_ bytes: Int64) -> String {
        SiftFormat.bytes(bytes)
    }
}

private struct StorageUsageBar: View {
    let value: Int64
    let total: Int64
    let emphasized: Bool

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    var body: some View {
        SiftMeterBar(fraction: ratio, fill: emphasized ? SiftColor.accent : SiftColor.accentDim)
            .accessibilityLabel("Share of scanned space")
            .accessibilityValue("\(Int((ratio * 100).rounded())) percent")
    }
}
