import SwiftUI

struct AppListView: View {
    private enum SortOrder {
        case size, name
    }

    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .size

    private var filteredApps: [InstalledApp] {
        let base: [InstalledApp]
        if searchText.isEmpty {
            base = appState.installedApps
        } else {
            let query = searchText.lowercased()
            base = appState.installedApps.filter {
                $0.appName.lowercased().contains(query) ||
                $0.bundleIdentifier.lowercased().contains(query)
            }
        }
        switch sortOrder {
        case .size:
            return base.sorted { $0.size != $1.size ? $0.size > $1.size : $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        case .name:
            return base.sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            SiftPageHeader(Text("Uninstaller"), eyebrow: Text("Installed applications")) {
                SiftSearchField(text: $searchText, prompt: Text("Search applications"))
                    .frame(width: 320)
                    .accessibilityIdentifier("uninstaller.search")
            }
            GeometryReader { proxy in
                // The list keeps the design's 420 pt until the detail card
                // would drop below the width its bottom bar needs.
                let listWidth = min(420, max(300, proxy.size.width - SiftSpacing.gutter - 520))
                HStack(alignment: .top, spacing: SiftSpacing.gutter) {
                    appList
                        .frame(width: listWidth)
                    fileDetail
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - App list (left card)

    private var appList: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text("\(appState.installedApps.count) applications")
                    .font(.sift(13, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                Spacer(minLength: 8)
                Button {
                    appState.loadInstalledApps()
                } label: {
                    SiftIcon.rotateCw.image(13).foregroundStyle(SiftColor.textSecondary)
                }
                .buttonStyle(.siftQuiet)
                .disabled(appState.isLoadingApps)
                .help("Refresh")
                .accessibilityLabel(Text("Refresh"))
                Button {
                    sortOrder = sortOrder == .size ? .name : .size
                } label: {
                    HStack(spacing: 6) {
                        SiftIcon.arrowDownWideNarrow.image(13)
                        Text(sortOrder == .size ? "By size" : "By name")
                            .font(.sift(11.5))
                    }
                    .foregroundStyle(SiftColor.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(Capsule(style: .continuous).fill(SiftColor.control))
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Change the sort order")
                .accessibilityIdentifier("uninstaller.sort")
            }
            .padding(.horizontal, 10)
            .frame(height: 40)

            listContent
                .frame(maxHeight: .infinity, alignment: .top)

            HStack(spacing: 8) {
                SiftIcon.info.image(13).foregroundStyle(SiftColor.textTertiary)
                Text("System apps and Apple's built-in apps are not listed")
                    .font(.sift(11.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous).fill(SiftColor.control))
        }
        .padding(10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: SiftRadius.card, style: .continuous).fill(SiftColor.card))
        .overlay(RoundedRectangle(cornerRadius: SiftRadius.card, style: .continuous).strokeBorder(SiftColor.stroke, lineWidth: 1))
    }

    @ViewBuilder
    private var listContent: some View {
        if appState.isLoadingApps && appState.installedApps.isEmpty {
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading installed apps...").siftStyle(.label)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.installedApps.isEmpty {
            VStack(spacing: 12) {
                SiftIconTile(icon: .layoutGrid, size: 38)
                Text("No Apps Found").siftStyle(.bodyStrong)
                Text("Could not find any installed applications.").siftStyle(.label)
                Button("Retry") { appState.loadInstalledApps() }
                    .buttonStyle(.sift(.secondary, compact: true))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let apps = filteredApps
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(apps) { app in
                            Button {
                                select(app)
                            } label: {
                                AppRow(app: app, isSelected: appState.selectedApp?.id == app.id)
                            }
                            .buttonStyle(.plain)
                            .id(app.id)
                            .accessibilityAddTraits(appState.selectedApp?.id == app.id ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.never)
                .focusable()
                .onMoveCommand { direction in
                    moveSelection(direction, in: apps, scroller: scroller)
                }
                .onAppear {
                    // Mounting already pointed at an externally selected app
                    // (Finder Services): bring it into view.
                    if let id = appState.selectedApp?.id { scroller.scrollTo(id, anchor: .center) }
                }
                .onChange(of: appState.selectedApp) { app in
                    guard let id = app?.id else { return }
                    withAnimation(SiftMotion.quick) { scroller.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func select(_ app: InstalledApp) {
        // Skip when the selection was just synced from an external (Finder
        // Services) hand-off that already scanned this app, so we don't fire
        // a redundant second scan.
        guard appState.selectedApp?.id != app.id else { return }
        appState.selectedApp = app
        appState.scanForAppFiles(app)
    }

    private func moveSelection(_ direction: MoveCommandDirection, in apps: [InstalledApp], scroller: ScrollViewProxy) {
        guard !apps.isEmpty else { return }
        let current = apps.firstIndex { $0.id == appState.selectedApp?.id }
        let next: Int
        switch direction {
        case .up: next = max(0, (current ?? apps.count) - 1)
        case .down: next = min(apps.count - 1, (current ?? -1) + 1)
        default: return
        }
        select(apps[next])
    }

    // MARK: - Detail (right card)

    @ViewBuilder
    private var fileDetail: some View {
        if let app = appState.selectedApp {
            AppFilesView(app: app)
                .id(app.id)
        } else {
            VStack(spacing: 12) {
                SiftIconTile(icon: .packageMinus, size: 44)
                Text("Select an App").siftStyle(.bodyStrong)
                Text("Select an app from the list to see all its related files across your system.")
                    .siftStyle(.label)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .siftSurface(.card, padding: 24)
        }
    }
}

// MARK: - Row

private struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIconTile(app: app, size: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: app.appName)
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .lineLimit(1)
                subtitle
                    .font(.sift(11))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(verbatim: app.formattedSize)
                .font(.siftMono(12))
                .foregroundStyle(isSelected ? SiftColor.accent : SiftColor.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 60)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SiftColor.selected)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SiftColor.selectedStroke, lineWidth: 1)
            }
        }
        .siftRowBackground(radius: 16)
    }

    /// "4.39, developer"; the bundle identifier when neither is known.
    private var subtitle: Text {
        switch (app.version, app.category) {
        case let (version?, category?):
            return Text(verbatim: "\(version), ") + Text(LocalizedStringKey(category))
        case let (version?, nil):
            return Text(verbatim: version)
        case let (nil, category?):
            return Text(LocalizedStringKey(category))
        case (nil, nil):
            return Text(verbatim: app.bundleIdentifier)
        }
    }
}

/// The app's own icon; a tinted initial when the bundle has no usable icon.
struct AppIconTile: View {
    let app: InstalledApp
    let size: CGFloat

    var body: some View {
        if app.icon.isValid, app.icon.size.width > 0 {
            Image(nsImage: app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Text(verbatim: String(app.appName.prefix(1)))
                .font(.siftDisplay(size * 0.42))
                .foregroundStyle(SiftColor.info)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.31, style: .continuous).fill(SiftColor.infoBackground)
                )
                .accessibilityHidden(true)
        }
    }
}
