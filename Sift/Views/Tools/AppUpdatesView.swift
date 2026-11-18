import SwiftUI

enum AppUpdateIdentityMatcher {
    static func baseToken(_ token: String) -> String {
        let cask = token.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? token
        return cask.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? cask
    }

    static func normalizedKey(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }

    static func matchingIndex(for token: String, appNames: [String]) -> Int? {
        let key = normalizedKey(baseToken(token))
        guard !key.isEmpty else { return nil }
        let matches = appNames.indices.filter { normalizedKey(appNames[$0]) == key }
        return matches.count == 1 ? matches[0] : nil
    }

    static func fallbackDisplayName(for token: String) -> String {
        let words = baseToken(token)
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? token : words.joined(separator: " ")
    }

    static func shouldShowTokenDetail(_ token: String) -> Bool {
        token.contains("@") || token.contains("/")
    }
}

@MainActor
struct AppUpdatesView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var updater: ApplicationUpdater
    @State private var showingUpgradeConfirmation = false
    @State private var confirmationSelection: [ManagedAppUpdate] = []

    init() {
        _updater = StateObject(wrappedValue: ApplicationUpdater())
    }

    init(updater: ApplicationUpdater) {
        _updater = StateObject(wrappedValue: updater)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
                    if let status = updater.statusMessage {
                        statusBanner(status)
                    }

                    content
                    sourceCard
                    unmanagedAppsCard
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !updater.updates.isEmpty {
                upgradeBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("App Updates")
        .alert("Upgrade selected apps?", isPresented: $showingUpgradeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(upgradeConfirmationLabel(count: confirmationSelection.count)) {
                let selection = confirmationSelection
                Task { await updater.upgrade(selection) }
            }
        } message: {
            Text(upgradeConfirmationMessage)
        }
        .onAppear {
            updater.refreshAvailability()        }
    }

    // MARK: Header

    private var header: some View {
        // A minute is the finest step a relative date needs: the eyebrow used
        // to tick every second because it rendered a live duration.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            SiftScreenHeader(
                Text("App Updates"),
                eyebrow: eyebrow(now: timeline.date),
                subtitle: Text("Review and update apps installed as Homebrew casks.")
            ) {
            // The first-run card carries its own Check button.
            if !isFirstRun {
                Button {
                    Task { await updater.checkForUpdates() }
                } label: {
                    Label {
                        Text(LocalizedStringKey(updater.hasChecked ? "Check Again" : "Check for Updates"))
                    } icon: {
                        SiftIcon.rotateCw.image(15).foregroundStyle(SiftColor.textSecondary)
                    }
                }
                .buttonStyle(.siftSecondary)
                .disabled(updater.isBusy || !updater.isHomebrewAvailable)
            }
            }
        }
    }

    /// "Last checked 1 minute ago" — one sentence, with the language's own
    /// word order around the date. A live duration (`style: .relative`) said
    /// "1 min, 19 secs" and ticked every second without ever saying "ago".
    static func checkedLabel(_ date: Date, now: Date = Date()) -> String {
        String(format: String(localized: "Last checked %@"), SiftFormat.relative(date, to: now))
    }

    private func eyebrow(now: Date) -> Text {
        guard let date = updater.lastCheckedAt else { return Text("Updates from Homebrew") }
        return Text(verbatim: Self.checkedLabel(date, now: now))
    }

    private var isFirstRun: Bool {
        updater.isHomebrewAvailable && !updater.isChecking && updater.errorMessage == nil
            && !updater.hasChecked && updater.updates.isEmpty
    }

    // MARK: Cards

    private var sourceCard: some View {
        HStack(alignment: .top, spacing: 12) {
            SiftIconTile(icon: .package, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("Updates from Homebrew")
                    .siftStyle(.cardTitle)
                Text("Checking asks Homebrew to refresh its package data as needed and contacts Homebrew's configured sources. Sift only lists cask apps managed by this Homebrew installation.")
                    .siftStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .siftSurface(.card)
    }

    @ViewBuilder
    private var content: some View {
        if !updater.isHomebrewAvailable {
            stateCard(
                title: "Homebrew not found",
                message: "Install Homebrew to check cask apps here. Apps from the App Store and direct downloads use their own update channels.",
                icon: .package,
                tone: .warning
            )
        } else if updater.isChecking {
            HStack(spacing: 14) {
                ProgressView()
                    .controlSize(.small)
                    .tint(SiftColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Checking Homebrew casks")
                        .siftStyle(.cardTitle)
                    Text("Refreshing package data and comparing installed versions.")
                        .siftStyle(.label)
                }
                Spacer()
            }
            .siftSurface(.card)
        } else if let error = updater.errorMessage {
            HStack(alignment: .top, spacing: 14) {
                SiftIconTile(icon: .triangleAlert, tone: .warning, size: 36)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't check for updates")
                        .siftStyle(.cardTitle)
                    Text(error)
                        .font(.siftMono(11))
                        .foregroundStyle(SiftColor.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try Again") {
                        Task { await updater.checkForUpdates() }
                    }
                    .buttonStyle(.sift(.secondary, compact: true))
                    .disabled(updater.isBusy)
                    .padding(.top, 2)
                }
                Spacer()
            }
            .siftSurface(.card)
        } else if updater.hasChecked && updater.updates.isEmpty {
            stateCard(
                title: "Homebrew apps are up to date",
                message: "No updates are currently available for the cask apps Homebrew manages.",
                icon: .check,
                tone: .success
            )
        } else if updater.updates.isEmpty {
            VStack(spacing: 14) {
                SiftIconTile(icon: .refresh, tone: .accent, size: 48)
                Text("Check installed cask apps")
                    .font(.siftDisplay(26))
                    .tracking(-0.4)
                    .foregroundStyle(SiftColor.textPrimary)
                Text("Sift will ask Homebrew for available versions when you start the check.")
                    .siftStyle(.body)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button {
                    Task { await updater.checkForUpdates() }
                } label: {
                    Label {
                        Text("Check for Updates")
                    } icon: {
                        SiftIcon.rotateCw.image(15)
                    }
                }
                .buttonStyle(.siftPrimary)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .siftSurface(.card)
        } else {
            updatesCard
        }
    }

    /// The Installers table: a column header, then 58 pt checkbox rows.
    private var updatesCard: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(updateCountTitle)
                    .siftStyle(.cardTitle)
                Spacer(minLength: 8)
                Text("Select the apps Homebrew should upgrade.")
                    .siftStyle(.label)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            SiftTableHeader {
                Color.clear.frame(width: 20, height: 1)
                Color.clear.frame(width: 36, height: 1)
                Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Available").frame(width: 120, alignment: .trailing)
            }

            LazyVStack(spacing: 2) {
                ForEach(updater.updates) { update in
                    updateRow(update)
                }
            }
        }
        .siftSurface(.card, padding: 10)
    }

    private func updateRow(_ update: ManagedAppUpdate) -> some View {
        let app = installedApp(for: update.token)
        let presentation = updater.caskPresentations[update.token]
        let displayName = app?.appName
            ?? presentation?.displayName
            ?? AppUpdateIdentityMatcher.fallbackDisplayName(for: update.token)
        let isSelected = updater.selectedTokens.contains(update.token)

        return HStack(spacing: 14) {
            Toggle(isOn: Binding(
                get: { updater.selectedTokens.contains(update.token) },
                set: { updater.setSelected($0, token: update.token) }
            )) { EmptyView() }
            .toggleStyle(.siftCheckbox)
            .disabled(update.isPinned || updater.isBusy)
            .opacity(update.isPinned ? 0.45 : 1)
            .accessibilityLabel("Select \(displayName)")

            appIcon(app?.icon ?? presentation?.icon, isPinned: update.isPinned, isSelected: isSelected)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(displayName)
                        .font(.sift(13.5, weight: 500))
                        .foregroundStyle(SiftColor.textPrimary)
                        .lineLimit(1)
                    if update.isPinned {
                        SiftStatusPill(Text("Pinned"), tone: .warning)
                    }
                    if presentation?.isBundleMissing == true {
                        SiftStatusPill(Text("App bundle missing"), tone: .warning, showsDot: false)
                    }
                }
                Text(updateDetail(update))
                    .siftStyle(.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(update.currentVersion)
                .font(.siftMono(12.5))
                .foregroundStyle(isSelected ? SiftColor.accent : SiftColor.textPrimary)
                .lineLimit(1)
                .frame(width: 120, alignment: .trailing)
                .accessibilityLabel(Text("Available") + Text(verbatim: " ") + Text(update.currentVersion))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 58)
        .siftRowBackground(accented: isSelected, radius: 16)
    }

    @ViewBuilder
    private func appIcon(_ icon: NSImage?, isPinned: Bool, isSelected: Bool) -> some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isSelected ? SiftColor.accentTint : SiftColor.control)
                )
                .accessibilityHidden(true)
        } else {
            SiftIconTile(icon: .appWindow, tone: isPinned ? .warning : (isSelected ? .accent : .neutral), size: 36)
                .accessibilityHidden(true)
        }
    }

    private func installedApp(for token: String) -> InstalledApp? {
        let names = appState.installedApps.map(\.appName)
        guard let index = AppUpdateIdentityMatcher.matchingIndex(for: token, appNames: names) else { return nil }
        return appState.installedApps[index]
    }

    private func displayName(for token: String) -> String {
        installedApp(for: token)?.appName
            ?? updater.caskPresentations[token]?.displayName
            ?? AppUpdateIdentityMatcher.fallbackDisplayName(for: token)
    }

    private func updateDetail(_ update: ManagedAppUpdate) -> String {
        let installed = String(localized: "Installed \(update.installedVersion)")
        guard AppUpdateIdentityMatcher.shouldShowTokenDetail(update.token) else { return installed }
        return String(localized: "\(update.token)  ·  \(installed)")
    }

    private var unmanagedAppsCard: some View {
        HStack(spacing: 12) {
            SiftIconTile(icon: .apple, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text("Apps outside Homebrew")
                    .siftStyle(.cardTitle)
                Text("Open the App Store updates page. Direct-download apps may provide their own updater.")
                    .siftStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button {
                updater.openAppStoreUpdates()
            } label: {
                Label {
                    Text("Open App Store Updates")
                } icon: {
                    SiftIcon.externalLink.image(14).foregroundStyle(SiftColor.textSecondary)
                }
            }
            .buttonStyle(.siftSecondary)
        }
        .siftSurface(.card)
    }

    private func stateCard(title: LocalizedStringKey, message: LocalizedStringKey, icon: SiftIcon, tone: SiftTone) -> some View {
        VStack(spacing: 12) {
            SiftIconTile(icon: icon, tone: tone, size: 48)
            Text(title)
                .font(.siftDisplay(26))
                .tracking(-0.4)
                .foregroundStyle(SiftColor.textPrimary)
            Text(message)
                .siftStyle(.body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .siftSurface(.card)
    }

    private func statusBanner(_ status: String) -> some View {
        SiftNoticeBanner(Text(status), icon: .check, tone: .success)
    }

    // MARK: Upgrade bar

    private var upgradeBar: some View {
        SiftSelectionBar(count: updater.selectedCount) {
            Text(updater.selectedCount == 0 ? String(localized: "Select apps to update") : selectedCountTitle)
                .font(.sift(13.5, weight: 500))
                .foregroundStyle(updater.selectedCount == 0 ? SiftColor.textTertiary : SiftColor.textPrimary)
                .lineLimit(1)
        } actions: {
            Button {
                confirmationSelection = updater.updates.filter {
                    updater.selectedTokens.contains($0.token) && !$0.isPinned
                }
                showingUpgradeConfirmation = true
            } label: {
                if updater.isUpgrading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(SiftColor.onAccent)
                        Text("Updating…")
                    }
                } else {
                    Label {
                        Text(upgradeConfirmationLabel(count: updater.selectedCount))
                    } icon: {
                        SiftIcon.download.image(15)
                    }
                }
            }
            .buttonStyle(.siftPrimary)
            .disabled(updater.selectedCount == 0 || updater.isBusy)
        }
    }

    private var updateCountTitle: String {
        updater.updates.count == 1 ? String(localized: "1 update available") : String(localized: "\(updater.updates.count) updates available")
    }

    private var selectedCountTitle: String {
        updater.selectedCount == 1 ? String(localized: "1 app selected") : String(localized: "\(updater.selectedCount) apps selected")
    }

    private func upgradeConfirmationLabel(count: Int) -> String {
        count == 1 ? String(localized: "Upgrade 1 App") : String(localized: "Upgrade \(count) Apps")
    }

    private var upgradeConfirmationMessage: String {
        let versions = confirmationSelection.map {
            String(localized: "\(displayName(for: $0.token)) \($0.installedVersion) to \($0.currentVersion)")
        }
        let selectionSummary: String
        if versions.count <= 5 {
            selectionSummary = versions.joined(separator: ", ")
        } else {
            selectionSummary = versions.prefix(5).joined(separator: ", ") + String(localized: ", and \(versions.count - 5) more")
        }
        return String(localized: "Homebrew will upgrade \(selectionSummary). It may quit running apps and remove superseded cask versions as part of its normal upgrade process.")
    }
}
