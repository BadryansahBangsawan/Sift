import AppKit
import SwiftUI

struct AppleFeaturesView: View {
    @EnvironmentObject private var appState: AppState
    private enum Page: String, CaseIterable {
        case features = "Features"
        case storage = "Storage"
    }

    private struct BackupSelection: Identifiable {
        let id = UUID()
        let backups: [DeviceBackup]
    }

    private let version = ProcessInfo.processInfo.operatingSystemVersion
    @State private var page = Page.features
    @State private var search = ""
    @State private var inventory: [AppleStorageItem]?
    @State private var inventoryTask: Task<Void, Never>?
    @State private var inventoryRunning = false
    @State private var inventoryNotice: String?
    @State private var backupService = DeviceBackupService()
    @State private var backups: [DeviceBackup] = []
    @State private var backupIssues: [String] = []
    @State private var backupSelection: Set<URL> = []
    @State private var backupTask: Task<Void, Never>?
    @State private var backupsRunning = false
    @State private var backupsScanned = false
    @State private var removalTask: Task<Void, Never>?
    @State private var removalNotice: String?
    @State private var pendingRemoval: BackupSelection?
    @State private var errorMessage: String?

    private var removalRunning: Bool { appState.deviceBackupRemovalInProgress }

    private var features: [AppleFeature] {
        AppleFeatureCatalog.features(for: version).filter {
            search.isEmpty || "\($0.title) \($0.summary) \($0.steps)".localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            SiftToolHeader(
                Text("Apple Features"),
                eyebrow: Text("Tools"),
                subtitle: Text("Review optional features and the storage used by Apple downloads.")
            ) {
                SiftSegmented(
                    selection: $page,
                    options: Page.allCases.map { (value: $0, label: Text(LocalizedStringKey($0.rawValue))) }
                )
                .disabled(removalRunning)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Apple Features section"))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
                    if removalRunning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Finishing backup removal. New scans are available when it stops.")
                                .siftStyle(.label)
                        }
                        .padding(.horizontal, 12)
                    }
                    if let result = appState.deviceBackupRemovalResult {
                        DeviceBackupRemovalReport(result: result) {
                            appState.deviceBackupRemovalResult = nil
                        }
                    }

                    if page == .features {
                        featuresContent
                    } else {
                        storageContent
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Apple Features")
        .alert("Couldn't complete the action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $pendingRemoval) { selection in
            DeviceBackupConfirmation(backups: selection.backups, canRemove: appState.canRemoveDeviceBackups) {
                pendingRemoval = nil
                removeBackups(selection.backups)
            }
        }
        .onDisappear {
            inventoryTask?.cancel()
            backupTask?.cancel()
            removalTask?.cancel()
        }
    }

    private var featuresContent: some View {
        VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
            SiftSearchField(text: $search, prompt: Text("Find a feature"))
                .accessibilityIdentifier("appleFeatures.search")

            VStack(alignment: .leading, spacing: 14) {
                SiftFootnote(
                    Text("Changes are made in Apple's settings. Sift does not detect or verify whether a feature is enabled."),
                    icon: .info
                )

                if features.isEmpty {
                    Text("No features match your search.")
                        .siftStyle(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                            AppleFeatureRow(feature: feature, version: version, openDestination: openDestination, openGuide: openURL)
                            if index < features.count - 1 { SiftRowDivider() }
                        }
                    }
                    .siftSurface(.inset, padding: 0)
                }

                Text("Availability also depends on your Mac model, language, region, account, and device management. Apple Intelligence requires a supported Mac with Apple silicon. Setting names can vary between macOS versions.")
                    .siftStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .siftSurface(.card)
        }
    }

    private var storageContent: some View {
        VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    SiftIconTile(icon: .download, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple downloads")
                            .siftStyle(.cardTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("Measure known locations without deleting files. These sizes are not a recoverable-space estimate.")
                            .siftStyle(.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(inventory == nil ? "Measure storage" : "Measure again", action: scanInventory)
                        .buttonStyle(.sift(.secondary, compact: true))
                        .disabled(inventoryRunning || removalRunning)
                        .accessibilityIdentifier("appleFeatures.measureStorage")
                }

                if inventoryRunning {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Measuring Apple storage…")
                            .siftStyle(.label)
                        Spacer()
                        Button("Stop") { inventoryTask?.cancel() }
                            .buttonStyle(.siftQuiet)
                    }
                }
                if let inventoryNotice {
                    Text(inventoryNotice)
                        .siftStyle(.label)
                }
                if let inventory {
                    VStack(spacing: 0) {
                        ForEach(Array(inventory.enumerated()), id: \.element.id) { index, item in
                            AppleStorageRow(item: item, reveal: reveal, openDestination: openDestination)
                            if index < inventory.count - 1 { SiftRowDivider() }
                        }
                    }
                    .siftSurface(.inset, padding: 0)
                }

                HStack(spacing: 8) {
                    Button("Storage settings") { openDestination("com.apple.settings.Storage") }
                    Button("Wallpaper settings") { openDestination("com.apple.Wallpaper-Settings.extension") }
                }
                .buttonStyle(.sift(.quiet, compact: true))
            }
            .siftSurface(.card)

            backupContent
        }
    }

    private var backupContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SiftIconTile(icon: .history, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iPhone and iPad backups")
                        .siftStyle(.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("Review complete local backups individually. Selected backups move to the Trash after confirmation.")
                        .siftStyle(.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(backupsScanned ? "Scan again" : "Find backups", action: scanBackups)
                    .buttonStyle(.sift(.secondary, compact: true))
                    .disabled(backupsRunning || removalRunning)
                    .accessibilityIdentifier("appleFeatures.findBackups")
            }
            if backupsRunning || removalRunning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(removalRunning ? "Checking and moving selected backups to the Trash…" : "Checking local backups…")
                        .siftStyle(.label)
                    Spacer()
                    if backupsRunning {
                        Button("Stop") { backupTask?.cancel() }
                            .buttonStyle(.siftQuiet)
                    }
                }
            }
            if let removalNotice {
                Text(removalNotice)
                    .siftStyle(.label)
            }
            if appState.scanState.isActive {
                SiftNotice(
                    icon: .info,
                    tone: .info,
                    message: Text("Backup removal is available after the current scan or cleanup finishes.")
                )
            }
            if !backupIssues.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(backupIssues.enumerated()), id: \.offset) { _, issue in
                            Text(issue).textSelection(.enabled)
                        }
                    }
                    .font(.siftMono(10.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 8) {
                        SiftIcon.triangleAlert.image(14).foregroundStyle(SiftColor.warning)
                        Text("\(backupIssues.count) backup locations could not be included")
                            .font(.sift(12))
                            .foregroundStyle(SiftColor.textSecondary)
                    }
                }
                .disclosureGroupStyle(.sift)
            }
            if backupsScanned && backups.isEmpty && !backupsRunning {
                Text(backupIssues.isEmpty ? "No complete local device backups were found." : "No backups are available to select. Review the scan issues above.")
                    .siftStyle(.label)
            }
            if !backups.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(backups.enumerated()), id: \.element.id) { index, backup in
                        backupRow(backup)
                        if index < backups.count - 1 { SiftRowDivider() }
                    }
                }
                .siftSurface(.inset, padding: 0)
                .disabled(backupsRunning || removalRunning)

                HStack(spacing: 12) {
                    Text("\(backupSelection.count) selected")
                        .siftStyle(.label)
                    Spacer()
                    Button("Review selected backups") {
                        let selection = backups.filter { backupSelection.contains($0.id) }
                        if !selection.isEmpty { pendingRemoval = BackupSelection(backups: selection) }
                    }
                    .buttonStyle(.siftPrimary)
                    .disabled(backupSelection.isEmpty || backupsRunning || !appState.canRemoveDeviceBackups)
                }
            }
        }
        .siftSurface(.card)
    }

    private func backupRow(_ backup: DeviceBackup) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle("Select backup \(backup.name)", isOn: Binding(
                get: { backupSelection.contains(backup.id) },
                set: { selected in
                    if selected { backupSelection.insert(backup.id) }
                    else { backupSelection.remove(backup.id) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.siftCheckbox)
            .frame(width: 20, alignment: .leading)
            .allowsHitTesting(!(backupsRunning || removalRunning))
            VStack(alignment: .leading, spacing: 3) {
                Text(backup.name)
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                    .textSelection(.enabled)
                Text(backup.url.path)
                    .siftStyle(.monoSmall)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Modified \(backup.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                    .siftStyle(.caption)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(ByteCountFormatter.string(fromByteCount: backup.allocatedSize, countStyle: .file))
                    .siftStyle(.rowValue)
                Button("Show in Finder") { reveal(backup.url) }
                    .buttonStyle(.sift(.secondary, compact: true))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @MainActor
    private func scanInventory() {
        guard !inventoryRunning, !removalRunning else { return }
        inventoryRunning = true
        inventoryNotice = nil
        inventoryTask = Task { @MainActor in
            defer { inventoryRunning = false }
            do {
                let result = try await AppleStorageService.scan()
                try Task.checkCancellation()
                inventory = result
            } catch is CancellationError {
                inventoryNotice = inventory == nil ? String(localized: "Storage measurement stopped.") : String(localized: "Storage measurement stopped. Previous results are still shown.")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func scanBackups() {
        guard !backupsRunning, !removalRunning else { return }
        backupsRunning = true
        backupsScanned = false
        backups = []
        backupIssues = []
        backupSelection = []
        removalNotice = nil
        backupTask = Task { @MainActor in
            defer { backupsRunning = false }
            do {
                let result = try await backupService.scan()
                try Task.checkCancellation()
                backups = result.backups
                backupIssues = result.issues
                backupsScanned = true
            } catch is CancellationError {
                removalNotice = String(localized: "Backup scan stopped. Scan again before selecting backups.")
                backups = []
                backupsScanned = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func removeBackups(_ selection: [DeviceBackup]) {
        guard !backupsRunning else { return }
        guard appState.canRemoveDeviceBackups else {
            removalNotice = String(localized: "Backup removal is available after the current scan or cleanup finishes.")
            return
        }
        let sharedState = appState
        sharedState.deviceBackupRemovalInProgress = true
        sharedState.deviceBackupRemovalResult = nil
        removalNotice = nil
        inventoryTask?.cancel()
        removalTask = Task { @MainActor in
            defer { sharedState.deviceBackupRemovalInProgress = false }
            do {
                let result = try await backupService.trash(selection)
                sharedState.deviceBackupRemovalResult = result
                let removed = Set(result.removedPaths)
                backups.removeAll { removed.contains($0.url.path) }
                backupSelection = []
                if !removed.isEmpty {
                    inventory = nil
                    inventoryNotice = String(localized: "Backups changed. Measure storage again for current sizes.")
                }
            } catch {
                sharedState.deviceBackupRemovalResult = DeviceBackupRemovalResult(
                    removedPaths: [], errors: [error.localizedDescription]
                )
            }
        }
    }

    private func openDestination(_ destination: String) {
        if destination.hasPrefix("application:") {
            let identifier = String(destination.dropFirst("application:".count))
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
                errorMessage = String(localized: "The app could not be found. Open it manually and follow the steps shown.")
                return
            }
            openURL(url)
        } else if let url = URL(string: "x-apple.systempreferences:\(destination)") {
            if !NSWorkspace.shared.open(url) {
                let fallback = URL(fileURLWithPath: "/System/Applications/System Settings.app")
                let opened = NSWorkspace.shared.open(fallback)
                errorMessage = opened
                    ? String(localized: "The settings shortcut could not be opened. System Settings is open; follow the steps shown to find the control.")
                    : String(localized: "System Settings could not be opened. Open it from the Apple menu and follow the steps shown.")
            }
        } else {
            errorMessage = String(localized: "The settings shortcut is unavailable. Open System Settings from the Apple menu.")
        }
    }

    private func openURL(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            errorMessage = String(localized: "Could not open \(url.absoluteString). Open the app or guide manually.")
        }
    }

    private func reveal(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = String(localized: "This location is no longer available or cannot be accessed. Scan again to refresh the results.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// A Settings-style grouped row that expands to show the steps.
private struct AppleFeatureRow: View {
    let feature: AppleFeature
    let version: OperatingSystemVersion
    let openDestination: (String) -> Void
    let openGuide: (URL) -> Void
    @State private var expanded = false

    private var available: Bool { feature.isAvailable(on: version) }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text(feature.steps)
                    .siftStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    Button(feature.destination.hasPrefix("application:") ? "Open Mail" : "Open Settings") {
                        openDestination(feature.destination)
                    }
                    .buttonStyle(.sift(.secondary, compact: true))
                    .disabled(!available)
                    Button("Apple guide") { openGuide(feature.guide) }
                        .buttonStyle(.sift(.quiet, compact: true))
                }
            }
            .padding(.top, 12)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(feature.title)
                        .font(.sift(13.5, weight: 500))
                        .foregroundStyle(SiftColor.textPrimary)
                    Spacer()
                    if !available {
                        SiftStatusPill(
                            Text("Requires macOS \(feature.minimumVersion.majorVersion).\(feature.minimumVersion.minorVersion)"),
                            tone: .neutral,
                            showsDot: false
                        )
                    }
                }
                Text(feature.summary)
                    .siftStyle(.label)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disclosureGroupStyle(.sift)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityIdentifier("appleFeatures.feature.\(feature.id)")
    }
}

private struct AppleStorageRow: View {
    let item: AppleStorageItem
    let reveal: (URL) -> Void
    let openDestination: (String) -> Void

    private var sizeDescription: String {
        switch item.status {
        case .notPresent: return String(localized: "Not found")
        case .unavailable: return String(localized: "Unavailable")
        case .complete, .partial:
            guard let bytes = item.allocatedBytes else { return String(localized: "Unknown") }
            if bytes == 0 {
                return item.status == .partial ? String(localized: "Not fully measured") : String(localized: "0 bytes")
            }
            let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            return item.status == .partial ? String(format: String(localized: "At least %@"), size) : size
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                Spacer()
                Text(sizeDescription)
                    .siftStyle(.rowValue)
            }
            Text(item.detail)
                .siftStyle(.label)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.path)
                .siftStyle(.monoSmall)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if item.status == .partial {
                Text("Partial measurement: \(item.skippedCount) skipped, \(item.inaccessibleCount) inaccessible.\(item.reachedLimit ? " Entry limit reached." : "")")
                    .font(.sift(11.5))
                    .foregroundStyle(SiftColor.warning)
            } else if item.status == .unavailable {
                Text("This location could not be measured. Permissions or protected system storage may prevent access.")
                    .siftStyle(.caption)
            }
            HStack(spacing: 8) {
                Button("Show in Finder") { reveal(item.url) }
                    .disabled(item.status == .notPresent || item.status == .unavailable)
                if item.kind == .screenSavers {
                    Button("Wallpaper settings") { openDestination("com.apple.Wallpaper-Settings.extension") }
                } else {
                    Button("Storage settings") { openDestination("com.apple.settings.Storage") }
                }
            }
            .buttonStyle(.sift(.secondary, compact: true))
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }
}

private struct DeviceBackupRemovalReport: View {
    let result: DeviceBackupRemovalResult
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SiftIconTile(icon: .trash2, tone: result.errors.isEmpty ? .success : .warning, size: 30)
                Text("\(result.removedPaths.count) backups moved to the Trash")
                    .siftStyle(.cardTitle)
                Spacer()
                Button("Dismiss report", action: dismiss)
                    .buttonStyle(.sift(.quiet, compact: true))
            }
            Text("Moving backups to the Trash does not free disk space. Emptying the Trash is a separate action.")
                .siftStyle(.label)
            ForEach(Array(result.errors.enumerated()), id: \.offset) { _, error in
                Text(error)
                    .font(.sift(12))
                    .foregroundStyle(SiftColor.warning)
                    .textSelection(.enabled)
            }
            if !result.removedPaths.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(result.removedPaths, id: \.self) { path in
                            Text(path)
                                .siftStyle(.monoSmall)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("Moved paths")
                        .font(.sift(12))
                        .foregroundStyle(SiftColor.textSecondary)
                }
                .disclosureGroupStyle(.sift)
            }
        }
        .siftSurface(.card)
    }
}

private struct DeviceBackupConfirmation: View {
    let backups: [DeviceBackup]
    let canRemove: Bool
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SiftIconTile(icon: .trash2, tone: .warning, size: 40)
                Text("Move \(backups.count) backups to the Trash?")
                    .font(.siftDisplay(26))
                    .tracking(-0.4)
                    .foregroundStyle(SiftColor.textPrimary)
            }
            Text("Removing your only backup prevents you from restoring that device from this Mac. Disconnect devices and stop any active backups before continuing.")
                .siftStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(backup.url.path)
                                .font(.siftMono(11))
                                .foregroundStyle(SiftColor.textPrimary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(ByteCountFormatter.string(fromByteCount: backup.allocatedSize, countStyle: .file))
                                .siftStyle(.mono)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            .frame(maxHeight: 220)
            .siftSurface(.inset, padding: 0)
            Text("Sift rechecks each selected backup before moving it. Emptying the Trash is a separate action.")
                .siftStyle(.label)
            if !canRemove {
                SiftNotice(
                    icon: .triangleAlert,
                    message: Text("Wait for the current scan or cleanup to finish before moving backups.")
                )
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.siftSecondary)
                Button("Move to Trash", role: .destructive, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRemove)
                    .buttonStyle(.siftPrimary)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(SiftColor.card)
    }
}
