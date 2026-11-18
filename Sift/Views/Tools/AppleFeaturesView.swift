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
    @State private var aiService = AppleIntelligenceService()
    @State private var aiStatus: AppleIntelligenceStatus?
    @State private var aiKeep: Set<String> = []
    @State private var aiTweaks: Set<String> = []
    @State private var aiPlan: AppleIntelligencePlan?
    @State private var aiResult: AppleIntelligenceApplyResult?
    @State private var aiNotice: String?
    @State private var aiWorking = false

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
        .sheet(item: $aiPlan) { plan in
            AppleIntelligenceReviewSheet(plan: plan, onApply: applyAppleIntelligence) {
                aiPlan = nil
            }
        }
        .onAppear(perform: refreshAppleIntelligence)
        .onDisappear {
            inventoryTask?.cancel()
            backupTask?.cancel()
            removalTask?.cancel()
        }
    }

    @ViewBuilder
    private var featuresContent: some View {
        if let status = aiStatus, status.supported {
            appleIntelligenceContent(status)
        } else {
            guidanceContent
        }
    }

    private var guidanceContent: some View {
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

    // MARK: Apple Intelligence

    private func appleIntelligenceContent(_ status: AppleIntelligenceStatus) -> some View {
        VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
            appleIntelligenceHeader(status)

            VStack(alignment: .leading, spacing: 14) {
                SiftCardHeader(Text("Features"), icon: .sparkles) {
                    Text("Keep what you use")
                        .siftStyle(.caption)
                }
                if let error = aiNotice {
                    SiftNotice(icon: .triangleAlert, tone: .warning, message: Text(verbatim: error))
                }
                VStack(spacing: 0) {
                    let features = AppleIntelligenceCatalog.availableFeatures(on: status.platform.version)
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        appleFeatureRow(feature, status: status)
                        if index < features.count - 1 { SiftRowDivider() }
                    }
                }
                .siftSurface(.inset, padding: 0)

                SiftFootnote(
                    Text("Turned-off features are locked by the configuration profile. Keeping a feature leaves its setting and the models it needs alone."),
                    icon: .info)
            }
            .siftSurface(.card)

            appleTweaksCard(status)

            HStack(spacing: 12) {
                Button("Undo everything", action: undoEverything)
                    .buttonStyle(.sift(.secondary))
                    .disabled(aiWorking)
                    .accessibilityIdentifier("appleFeatures.undoAll")
                Spacer()
                Text("Models come back only when macOS downloads them again after the profile is removed.")
                    .siftStyle(.caption)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            if let result = aiResult { appleIntelligenceResult(result) }

            VStack(alignment: .leading, spacing: 8) {
                SiftFootnote(
                    Text("Storage settings may keep counting the models until macOS deletes them. If a macOS update is waiting for the blocked downloads, it can take about two hours to finish; sleep pauses that wait."),
                    icon: .info)
                SiftFootnote(
                    Text("Sift writes the configuration profile and opens it. You approve it in System Settings; Sift never installs it. Nothing changes until you confirm the review."),
                    icon: .lockKeyhole)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("appleFeatures.appleIntelligence")
    }

    private func appleIntelligenceHeader(_ status: AppleIntelligenceStatus) -> some View {
        let modelSize = status.totalModelBytes.map {
            SiftFormat.bytes($0)
        } ?? String(localized: "Unknown")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                SiftIconTile(icon: .sparkles, tone: .accent, size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Intelligence")
                        .siftStyle(.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 8) {
                        SiftStatusPill(overallLabel(status.overall), tone: overallTone(status.overall))
                        if status.profile.on {
                            SiftStatusPill(Text("Profile installed"), tone: .info, showsDot: false)
                        }
                    }
                    Text("Sift asks macOS to delete the models and blocks their download URL.")
                        .siftStyle(.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: modelSize)
                        .font(.siftMono(18))
                        .foregroundStyle(SiftColor.textPrimary)
                    Text("models on disk")
                        .siftStyle(.caption)
                }
            }
            HStack(spacing: 10) {
                Button("Turn off Apple Intelligence…") { reviewAppleIntelligence() }
                    .buttonStyle(.siftPrimary)
                    .disabled(aiWorking)
                    .accessibilityIdentifier("appleFeatures.turnOff")
                Button("Turn back on") { undoAppleIntelligence() }
                    .buttonStyle(.sift(.secondary))
                    .disabled(aiWorking)
                    .accessibilityIdentifier("appleFeatures.turnOn")
                Spacer()
                if aiWorking {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .siftSurface(.hero)
    }

    private func appleFeatureRow(
        _ feature: AppleIntelligenceFeature, status: AppleIntelligenceStatus
    ) -> some View {
        let bytes = status.bytes(for: feature)
        // Most features share the foundation models; only show a size that is on disk.
        let size = bytes.flatMap { $0 > 0 ? SiftFormat.bytes($0) : nil }
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: feature.title)
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                if let size {
                    Text(verbatim: size)
                        .siftStyle(.monoValue)
                } else {
                    Text("Model size unknown")
                        .siftStyle(.caption)
                }
            }
            Spacer(minLength: 12)
            Toggle(isOn: Binding(
                get: { aiKeep.contains(feature.id) },
                set: { keep in
                    if keep { aiKeep.insert(feature.id) } else { aiKeep.remove(feature.id) }
                }
            )) { EmptyView() }
            .toggleStyle(.siftSwitch)
            .accessibilityLabel(Text("Keep \(feature.title)"))
            .disabled(aiWorking)
            .accessibilityIdentifier("appleFeatures.keep.\(feature.id)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func appleTweaksCard(_ status: AppleIntelligenceStatus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SiftIconTile(icon: .shieldCheck, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Privacy & pop-ups (optional)")
                        .siftStyle(.cardTitle)
                        .accessibilityAddTraits(.isHeader)
                    Text("Applied here, journaled first, and undone exactly as they were.")
                        .siftStyle(.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Recommended") {
                    aiKeep = []
                    aiTweaks = Set(
                        AppleTweaks.preset(.recommended, on: status.platform.version).map(\.id))
                }
                .buttonStyle(.sift(.secondary, compact: true))
                .disabled(aiWorking)
            }
            VStack(spacing: 0) {
                let tweaks = AppleTweaks.all.filter { $0.isAvailable(on: status.platform.version) }
                ForEach(Array(tweaks.enumerated()), id: \.element.id) { index, tweak in
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: tweak.title)
                                .font(.sift(13.5, weight: 500))
                                .foregroundStyle(SiftColor.textPrimary)
                            Text(verbatim: tweak.detail)
                                .siftStyle(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            if let caveat = tweak.caveat {
                                Text(verbatim: caveat)
                                    .siftStyle(.caption)
                                    .foregroundStyle(SiftColor.warning)
                            }
                        }
                        Spacer(minLength: 12)
                        Toggle(isOn: Binding(
                            get: { aiTweaks.contains(tweak.id) },
                            set: { apply in
                                if apply { aiTweaks.insert(tweak.id) } else { aiTweaks.remove(tweak.id) }
                            }
                        )) { EmptyView() }
                        .toggleStyle(.siftSwitch)
                        .accessibilityLabel(Text("Apply \(tweak.title)"))
                        .disabled(aiWorking)
                        .accessibilityIdentifier("appleFeatures.tweak.\(tweak.id)")
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    if index < tweaks.count - 1 { SiftRowDivider() }
                }
            }
            .siftSurface(.inset, padding: 0)
        }
        .siftSurface(.card)
    }

    private func appleIntelligenceResult(_ result: AppleIntelligenceApplyResult) -> some View {
        let complete = result.succeeded
        return VStack(alignment: .leading, spacing: 10) {
            SiftNotice(
                icon: complete ? .check : .triangleAlert,
                tone: complete ? .success : .warning,
                title: complete ? Text("Turned off") : Text("Partly done"),
                message: Text(verbatim: resultMessage(result))
            )
            HStack(spacing: 8) {
                if result.profileURL != nil {
                    Button("Open Profiles") {
                        openDestination("com.apple.Profiles-Settings.extension")
                    }
                    .buttonStyle(.sift(.secondary, compact: true))
                }
                Button("Done") { aiResult = nil }
                    .buttonStyle(.siftQuiet)
            }
        }
        .siftSurface(.card)
    }

    private func resultMessage(_ result: AppleIntelligenceApplyResult) -> String {
        var parts: [String] = []
        if let url = result.profileURL {
            parts.append(
                String(localized: "Approve the profile in System Settings > Privacy & Security > Profiles. It is at \(url.path)."))
        }
        if !result.modelsRemoved.isEmpty {
            parts.append(
                String(localized: "\(result.modelsRemoved.count) model sets were released. macOS deletes the files on its own schedule."))
        }
        parts += result.problems
        parts += result.modelProblems
        if parts.isEmpty { parts.append(String(localized: "Everything requested was applied.")) }
        return parts.joined(separator: "\n")
    }

    private func overallLabel(_ overall: AppleIntelligenceOverall) -> Text {
        switch overall {
        case .on: return Text("On")
        case .off: return Text("Off")
        case .partlyOff: return Text("Partly off")
        case .unavailable: return Text("Not available on this macOS")
        }
    }

    private func overallTone(_ overall: AppleIntelligenceOverall) -> SiftTone {
        switch overall {
        case .on: return .info
        case .off: return .success
        case .partlyOff: return .warning
        case .unavailable: return .neutral
        }
    }

    /// The asset service is a synchronous private API; never ask it on the main thread.
    private func refreshAppleIntelligence() {
        let service = aiService
        Task { @MainActor in
            aiStatus = await Task.detached(priority: .userInitiated) { service.status() }.value
        }
    }

    private func reviewAppleIntelligence() {
        let service = aiService
        let selection = AppleIntelligenceSelection(keep: aiKeep, tweaks: aiTweaks)
        let plan = service.plan(selection)
        if plan.isEmpty {
            aiNotice = String(localized: "This Mac already matches the review.")
        } else {
            aiNotice = nil
            aiPlan = plan
        }
    }

    private func applyAppleIntelligence() {
        guard let plan = aiPlan, !aiWorking else { return }
        aiWorking = true
        aiNotice = nil
        let service = aiService
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                service.apply(plan)
            }.value
            aiResult = result
            aiWorking = false
            aiPlan = nil
            aiStatus = await Task.detached(priority: .userInitiated) { service.status() }.value
        }
    }

    private func undoAppleIntelligence() {
        guard !aiWorking else { return }
        aiWorking = true
        let service = aiService
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                service.undo(.appleIntelligence)
            }.value
            aiWorking = false
            aiNotice = nil
            aiResult = AppleIntelligenceApplyResult(problems: result.problems)
            aiStatus = await Task.detached(priority: .userInitiated) { service.status() }.value
            openDestination("com.apple.Profiles-Settings.extension")
        }
    }

    private func undoEverything() {
        guard !aiWorking else { return }
        aiWorking = true
        let service = aiService
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                service.undo(.everything)
            }.value
            aiWorking = false
            aiNotice = result.problems.isEmpty
                ? String(localized: "Settings restored. Remove the Sift profile in System Settings > Privacy & Security > Profiles to turn Apple Intelligence back on.")
                : result.problems.joined(separator: "\n")
            aiResult = nil
            aiStatus = await Task.detached(priority: .userInitiated) { service.status() }.value
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
                Text(SiftFormat.bytes(backup.allocatedSize))
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
            let size = SiftFormat.bytes(bytes)
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
                            Text(SiftFormat.bytes(backup.allocatedSize))
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

/// The exact list of changes before anything is applied.
private struct AppleIntelligenceReviewSheet: View {
    let plan: AppleIntelligencePlan
    let onApply: () -> Void
    let onCancel: () -> Void

    private var profileChanges: [AppleIntelligenceChange] { plan.changes.filter(\.isProfile) }
    private var localChanges: [AppleIntelligenceChange] { plan.changes.filter { !$0.isProfile } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review changes")
                    .siftStyle(.metricSmall)
                Text("Nothing is applied until you choose Turn off.")
                    .siftStyle(.label)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !plan.featuresTurnedOff.isEmpty {
                        section(
                            "Apple Intelligence off",
                            detail: "Locked by the profile: \(plan.featuresTurnedOff.count) features.",
                            changes: profileChanges.filter { $0.id.hasPrefix("feature:") })
                    }
                    if !plan.tweaks.isEmpty {
                        section(
                            "Privacy and pop-ups",
                            detail: "Journaled first, so undo puts the old values back.",
                            changes: plan.changes.filter { $0.id.hasPrefix("tweak:") })
                    }
                    if !plan.modelSets.isEmpty {
                        let size = plan.reportedModelBytes.map {
                            SiftFormat.bytes($0)
                        }
                        section(
                            "Models to delete",
                            detail: size.map { String(localized: "\(plan.modelSets.count) sets, about \($0) reported by the service.") }
                                ?? String(localized: "\(plan.modelSets.count) sets; the service did not report every size."),
                            changes: localChanges.filter { $0.id.hasPrefix("model:") })
                    }
                    if plan.profile != nil {
                        section(
                            "Configuration profile",
                            detail: "The profile points the removed sets' download URL at a closed local port and holds the locked settings. You approve it in System Settings.",
                            changes: profileChanges.filter { $0.id == "profile" })
                    }
                }
            }
            .frame(maxHeight: 380)

            SiftFootnote(
                Text("macOS asks you to approve the profile. Removing the profile turns Apple Intelligence back on; models come back only when macOS downloads them again."),
                icon: .info)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.siftSecondary)
                Button("Turn off", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.siftPrimary)
            }
        }
        .padding(24)
        .frame(width: 620, height: 560, alignment: .topLeading)
        .background(SiftColor.card)
    }

    private func section(
        _ title: String, detail: String, changes: [AppleIntelligenceChange]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(title))
                .siftStyle(.cardTitle)
            Text(verbatim: detail)
                .siftStyle(.label)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
                    HStack(alignment: .top, spacing: 10) {
                        SiftDot(tone: change.isProfile ? .accent : .warning)
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: change.title)
                                .font(.sift(12.5, weight: 500))
                                .foregroundStyle(SiftColor.textPrimary)
                            Text(verbatim: change.detail)
                                .siftStyle(.monoSmall)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    if index < changes.count - 1 { SiftRowDivider(inset: 14) }
                }
            }
            .siftSurface(.inset, padding: 0)
        }
    }
}
