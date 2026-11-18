import AppKit
import SwiftUI

@MainActor
final class SimilarPhotosViewModel: ObservableObject {
    enum Phase {
        case idle
        case scanning
        case loaded
        case failed(String)
        case cancelled
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var folder: URL?
    @Published private(set) var result: SimilarPhotoScanResult?
    @Published private(set) var progress: SimilarPhotoScanProgress?

    private let finder: SimilarPhotoFinder
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()

    init(finder: SimilarPhotoFinder = SimilarPhotoFinder()) {
        self.finder = finder
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a photo folder")
        panel.message = String(localized: "Sift compares local image thumbnails without changing your photos.")
        panel.prompt = String(localized: "Scan Photos")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        startScan(folder: url.standardizedFileURL)
    }

    func rescan() {
        guard let folder else { return }
        startScan(folder: folder)
    }

    func cancel() {
        guard isScanning else { return }
        scanTask?.cancel()
        phase = .cancelled
        progress = nil
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func startScan(folder: URL) {
        scanTask?.cancel()
        let id = UUID()
        scanID = id
        self.folder = folder
        result = nil
        progress = SimilarPhotoScanProgress(
            phase: .discovering,
            entriesVisited: 0,
            candidatesFound: 0,
            photosAnalyzed: 0,
            currentURL: folder
        )
        phase = .scanning

        scanTask = Task { [weak self, finder] in
            do {
                let result = try await finder.scan(folder: folder) { [weak self] progress in
                    await self?.receive(progress, scanID: id)
                }
                guard let self, self.scanID == id, !Task.isCancelled else { return }
                self.result = result
                self.progress = nil
                self.phase = .loaded
            } catch is CancellationError {
                guard let self, self.scanID == id, self.isScanning else { return }
                self.progress = nil
                self.phase = .cancelled
            } catch {
                guard let self, self.scanID == id else { return }
                self.progress = nil
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func receive(_ progress: SimilarPhotoScanProgress, scanID: UUID) {
        guard self.scanID == scanID, isScanning else { return }
        self.progress = progress
    }
}

struct SimilarPhotosView: View {
    @StateObject private var model: SimilarPhotosViewModel

    init(finder: SimilarPhotoFinder = SimilarPhotoFinder()) {
        _model = StateObject(wrappedValue: SimilarPhotosViewModel(finder: finder))
    }

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            header
            if let folder = model.folder {
                locationBar(folder)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Similar Photos")
        .onDisappear {
            model.cancel()
        }
    }

    private var header: some View {
        SiftToolHeader(
            Text("Similar Photos"),
            eyebrow: Text("Tools"),
            subtitle: Text("Find visually related shots in a folder and review them side by side.")
        ) {
            Button {
                model.chooseFolder()
            } label: {
                Label(model.folder == nil ? "Choose Folder" : "Choose Another Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.siftPrimary)
            .disabled(model.isScanning)
        }
    }

    private func locationBar(_ folder: URL) -> some View {
        SiftPathBar(path: folder.path) {
            Button {
                model.reveal(folder)
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
                title: "Photos could not be compared",
                message: message,
                icon: .triangleAlert,
                tone: .warning
            )
        case .cancelled:
            messageState(
                title: "Scan stopped",
                message: String(localized: "No photos were changed. You can scan the folder again at any time."),
                icon: .info,
                tone: .neutral
            )
        }
    }

    private var idleState: some View {
        SiftEmptyState(
            icon: .images,
            title: Text("Choose a folder of photos"),
            message: Text("Compare local photos by appearance and review likely matches side by side. Photos are never uploaded or deleted."),
            footnote: Text("Up to 500 photos and 10,000 directory entries per scan. Symbolic links, packages, hidden files, and cloud-only items are skipped.")
        )
    }

    private var scanningState: some View {
        SiftScanningCard(
            title: Text(verbatim: progressTitle),
            detail: Text(verbatim: model.progress?.currentURL?.lastPathComponent ?? String(localized: "Preparing visual comparison")),
            stop: { model.cancel() }
        ) {
            SiftCountPill(String(localized: "\(model.progress?.entriesVisited ?? 0) items"))
            SiftCountPill(String(localized: "\(model.progress?.candidatesFound ?? 0) photos"))
            if let progress = model.progress, progress.photosAnalyzed > 0 {
                SiftCountPill(String(localized: "\(progress.photosAnalyzed) compared"), tone: .accent)
            }
        }
    }

    private var progressTitle: String {
        switch model.progress?.phase {
        case .discovering, .none:
            return String(localized: "Finding local photos")
        case .analyzing:
            return String(localized: "Building visual signatures")
        case .comparing:
            return String(localized: "Grouping similar shots")
        }
    }

    private func resultView(_ result: SimilarPhotoScanResult) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SiftSpacing.gutter) {
                summaryCard(result)

                SiftNotice(
                    icon: .scanSearch,
                    tone: .info,
                    title: Text("Review the groups before acting"),
                    message: Text("Similarity is a visual estimate, not proof that two files are identical. Use Show in Finder to compare originals at full quality.")
                )

                if result.groups.isEmpty {
                    SiftEmptyState(
                        icon: .check,
                        tone: .success,
                        title: Text("No similar groups found"),
                        message: Text("The analyzed photos did not meet Sift's visual similarity threshold.")
                    )
                } else {
                    Text("Suggested groups")
                        .font(.sift(12.5))
                        .foregroundStyle(SiftColor.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(result.groups.enumerated()), id: \.element.id) { index, group in
                        SimilarPhotoGroupCard(index: index + 1, group: group, onReveal: model.reveal)
                    }
                }
            }
            .padding(.bottom, 2)
        }
    }

    private func summaryCard(_ result: SimilarPhotoScanResult) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                SiftStat("\(result.groups.count)", label: Text(result.groups.count == 1 ? "similar group" : "similar groups"))
                HStack(spacing: 8) {
                    SiftCountPill(String(localized: "\(result.photosAnalyzed) analyzed · \(result.matchedPhotoCount) matched"))
                    SiftCountPill(String(localized: "\(Self.format(result.matchedPhotoSize)) in matched photos · \(result.skippedItems) skipped"))
                }
            }

            Spacer()

            if result.isPartial {
                SiftStatusPill(Text("Sample limit reached"), tone: .warning)
            }
        }
        .siftSurface(.card)
    }

    private func messageState(title: LocalizedStringKey, message: String, icon: SiftIcon, tone: SiftTone) -> some View {
        SiftEmptyState(icon: icon, tone: tone, title: Text(title), message: Text(message)) {
            if model.folder != nil {
                Button("Scan Again") {
                    model.rescan()
                }
                .buttonStyle(.siftSecondary)
            }
        }
    }

    private static func format(_ bytes: Int64) -> String {
        SiftFormat.bytes(bytes)
    }
}

private struct SimilarPhotoGroupCard: View {
    let index: Int
    let group: SimilarPhotoGroup
    let onReveal: (URL) -> Void

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 250), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                SiftIconTile(icon: .images, tone: .accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Group \(index)")
                        .siftStyle(.cardTitle)
                    Text("\(group.photos.count) photos · \(Self.format(group.totalSize))")
                        .siftStyle(.monoSmall)
                }
                Spacer()
                SiftStatusPill(
                    Text(verbatim: String(localized: "\(Int((group.similarity * 100).rounded()))% visual score")),
                    tone: .accent
                )
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(group.photos) { photo in
                    SimilarPhotoTile(photo: photo, onReveal: { onReveal(photo.url) })
                }
            }
        }
        .siftSurface(.card)
    }

    private static func format(_ bytes: Int64) -> String {
        SiftFormat.bytes(bytes)
    }
}

private struct SimilarPhotoTile: View {
    let photo: SimilarPhoto
    let onReveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SiftColor.track)
                if let image = NSImage(data: photo.thumbnailData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    SiftIcon.photo.image(28)
                        .foregroundStyle(SiftColor.textTertiary)
                }
            }
            .frame(height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(photo.url.lastPathComponent)
                    .font(.sift(12.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(photo.url.path)

                HStack(spacing: 5) {
                    Text("\(photo.pixelWidth) × \(photo.pixelHeight)")
                    Text("·")
                    Text(Self.format(photo.size))
                    Spacer(minLength: 0)
                }
                .siftStyle(.monoSmall)
            }

            Button(action: onReveal) {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.sift(.secondary, compact: true))
            .accessibilityLabel("Show \(photo.url.lastPathComponent) in Finder")
        }
        .padding(10)
        .siftSurface(.inset, padding: 0)
        .contextMenu {
            Button("Show in Finder", action: onReveal)
        }
    }

    private static func format(_ bytes: Int64) -> String {
        SiftFormat.bytes(bytes)
    }
}
