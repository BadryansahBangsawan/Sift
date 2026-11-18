import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Pages

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, cleaning, schedule, appearance, permissions, updates

    /// Remembers the open page across accent changes (which rebuild the tree)
    /// and relaunches.
    static let storageKey = "PureMac.SettingsPage"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .cleaning: return "Cleaning"
        case .schedule: return "Schedule"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        case .updates: return "Updates"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .general: return "Startup, language, the menu bar monitor and sound."
        case .cleaning: return "What Sift looks for, and what it leaves alone."
        case .schedule: return "Let Sift scan on its own, on a timetable you set."
        case .appearance: return "Theme and accent color for every window."
        case .permissions: return "What macOS lets Sift read and control."
        case .updates: return "Your version, release checks and how to install updates."
        }
    }

    var icon: SiftIcon {
        switch self {
        case .general: return .slidersHorizontal
        case .cleaning: return .sparkles
        case .schedule: return .calendarClock
        case .appearance: return .palette
        case .permissions: return .lockKeyhole
        case .updates: return .download
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    /// The dedicated macOS Settings window owns its permission sheet. The main
    /// window already presents the shared coordinator's sheet for every page.
    var standalone = false
    @ObservedObject private var permission = PermissionCoordinator.shared
    @ObservedObject private var accentStore = AccentStore.shared
    @AppStorage(SettingsPage.storageKey) private var pageRaw = SettingsPage.general.rawValue

    private var page: SettingsPage { SettingsPage(rawValue: pageRaw) ?? .general }

    var body: some View {
        VStack(spacing: 14) {
            // The standard Settings window already carries the title; only the
            // main-window page repeats it as a header.
            if !standalone {
                SiftPageHeader(Text("Settings"), eyebrow: Text("Preferences")) { supportFolderChip }
            }
            HStack(alignment: .top, spacing: SiftSpacing.gutter) {
                SettingsNav(selection: Binding(get: { page }, set: { pageRaw = $0.rawValue }), width: standalone ? 208 : 248)
                SettingsPanel(page: page, permissionPresentation: standalone ? .settingsWindow : .mainWindow)
            }
        }
        .padding(standalone ? SiftSpacing.gutter : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(standalone ? SiftColor.window.ignoresSafeArea() : nil)
        .tint(SiftColor.accent)
        // The main window rebuilds its tree when the accent changes; the
        // standalone Settings window has to do it itself.
        .id(standalone ? accentStore.accent.rawValue : "main")
        .navigationTitle("Settings")
        .onAppear { showRequestedUpdates() }
        .onChange(of: appState.showUpdateSettings) { _ in showRequestedUpdates() }
        .sheet(isPresented: Binding(
            get: { standalone && permission.isRequesting && permission.presentation == .settingsWindow },
            set: { if !$0 && standalone && permission.presentation == .settingsWindow { permission.dismiss(callRetry: false) } }
        )) { PermissionSheet() }
    }

    /// Where Sift keeps its own files (cleanup history), shortened with `~`.
    private var supportFolderChip: some View {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sift", isDirectory: true)
        return HStack(spacing: 8) {
            SiftIcon.hardDrive.image(13)
            Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)
                .font(.siftMono(11))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(SiftColor.textTertiary)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Capsule(style: .continuous).fill(SiftColor.card))
        .overlay(Capsule(style: .continuous).strokeBorder(SiftColor.stroke, lineWidth: 1))
        .help(folder.path)
        .textSelection(.enabled)
    }

    private func showRequestedUpdates() {
        if !standalone && appState.showUpdateSettings {
            pageRaw = SettingsPage.updates.rawValue
            appState.showUpdateSettings = false
        }
    }
}

// MARK: - Navigation

private struct SettingsNav: View {
    @Binding var selection: SettingsPage
    let width: CGFloat

    private static var minimumSystem: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String ?? "13"
        return raw.split(separator: ".").first.map(String.init) ?? "13"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { page in
                Button { selection = page } label: {
                    SettingsNavRow(page: page, isSelected: page == selection)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(page.title))
                .accessibilityAddTraits(page == selection ? .isSelected : [])
                .accessibilityIdentifier("settings.page.\(page.rawValue)")
            }
            Spacer(minLength: 12)
            footer
        }
        .padding(10)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .siftSurface(.card, padding: 0)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.tabs")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            SiftAppTile(size: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Version \(UpdateService.installedVersion)")
                    .font(.sift(12, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                Text("macOS \(Self.minimumSystem) or later")
                    .font(.sift(10.5))
                    .foregroundStyle(SiftColor.textTertiary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous).fill(SiftColor.control))
        .accessibilityElement(children: .combine)
        .textSelection(.enabled)
    }
}

private struct SettingsNavRow: View {
    let page: SettingsPage
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            page.icon.image(16)
                .foregroundStyle(isSelected ? SiftColor.accent : SiftColor.icon)
            Text(page.title)
                .font(.sift(13, weight: isSelected ? 500 : 400))
                .foregroundStyle(isSelected || hovering ? SiftColor.textPrimary : SiftColor.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                SiftIcon.chevronRight.image(14).foregroundStyle(SiftColor.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous)
                .fill(isSelected ? SiftColor.selected : hovering ? SiftColor.selected.opacity(0.55) : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous))
        .onHover { hovering = $0 }
    }
}

// MARK: - Panel

private struct SettingsPanel: View {
    let page: SettingsPage
    let permissionPresentation: PermissionCoordinator.Presentation
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                header
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .siftSurface(.card, padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: SiftRadius.card, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title)
                    .font(.siftDisplay(24))
                    .tracking(-0.4)
                    .foregroundStyle(SiftColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(page.subtitle)
                    .font(.sift(12.5))
                    .foregroundStyle(SiftColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SiftCheckPill(text: Text("Most changes apply immediately"))
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .general: GeneralSettingsView()
        case .cleaning: CleaningSettingsView()
        case .schedule: ScheduleSettingsView(scheduler: appState.scheduler)
        case .appearance: AppearanceAccentSettings()
        case .permissions: PermissionsSettingsView(presentation: permissionPresentation)
        case .updates:
            AppUpdateSettingsView()
            AboutSettingsView()
        }
    }
}

// MARK: - General

enum SearchSensitivity: String, CaseIterable, Identifiable, Codable {
    case strict = "Strict"
    case enhanced = "Enhanced"
    case deep = "Deep"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .strict: return "Exact bundle ID and name matches only. Safest option."
        case .enhanced: return "Includes partial name matching and bundle ID components."
        case .deep: return "Includes company name, entitlements, and team identifier matching."
        }
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("settings.general.launchAtLogin") private var launchAtLogin = false
    @AppStorage("settings.general.searchSensitivity") private var sensitivity: SearchSensitivity = .enhanced
    @AppStorage("settings.general.menuBarMonitor") private var menuBarMonitor = false
    @AppStorage(Haptics.soundEffectsKey) private var soundEffects = true
    @AppStorage(AppLanguage.preferenceKey) private var appLanguageRaw = AppLanguage.current.rawValue
    private var languageNeedsRelaunch: Bool { appState.settingsNeedLanguageRestart }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SiftSettingsLabel(title: Text("Startup"))
        SiftSettingsGroup {
            SiftSettingsToggleRow(Text("Launch Sift at login"),
                                  detail: Text("Opens quietly when you sign in to your Mac"),
                                  isOn: launchAtLoginBinding)
        }

        SiftSettingsLabel(title: Text("Language"))
        SiftSettingsGroup {
            SiftSettingsRow(Text("Language"), detail: Text("A new language applies after Sift restarts")) {
                SiftDropdown(selection: appLanguageBinding, options: AppLanguage.allCases) {
                    String(localized: String.LocalizationValue($0.displayName))
                }
                .fixedSize()
            }
            if languageNeedsRelaunch {
                SiftSettingsDivider()
                SiftSettingsRow(Text("Restart Sift to apply the selected language.")) {
                    Button("Relaunch Now") { relaunchApp() }
                        .buttonStyle(.sift(.primary, compact: true))
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : SiftMotion.snappy, value: languageNeedsRelaunch)

        SiftSettingsLabel(title: Text("Menu bar and sound"))
        SiftSettingsGroup {
            SiftSettingsToggleRow(
                Text("Show system monitor in menu bar"),
                detail: Text("Live CPU, memory, and disk meters in the menu bar. Sift keeps running in the background while this is on."),
                isOn: menuBarMonitorBinding
            )
            SiftSettingsDivider()
            SiftSettingsToggleRow(Text("Play sound effects"),
                                  detail: Text("A chime when a cleanup finishes, a tone when it fails"),
                                  isOn: $soundEffects)
        }

        SiftSettingsLabel(title: Text("App scanning"))
        SiftSettingsGroup {
            SiftSettingsRow(Text("Search sensitivity"), detail: Text(LocalizedStringKey(sensitivity.description))) {
                SiftSegmented(selection: $sensitivity, options: SearchSensitivity.allCases.map {
                    (value: $0, label: Text(LocalizedStringKey($0.rawValue)))
                })
                .fixedSize()
            }
        }
    }

    private var menuBarMonitorBinding: Binding<Bool> {
        Binding(
            get: { menuBarMonitor },
            set: { newValue in
                menuBarMonitor = newValue
                // Tell AppDelegate to add/remove the status item without relaunch.
                NotificationCenter.default.post(name: .pureMacMenuBarMonitorChanged, object: nil)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                launchAtLogin = newValue
                toggleLaunchAtLogin(newValue)
            }
        )
    }

    private var appLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: appLanguageRaw) ?? .system },
            set: { newValue in
                appLanguageRaw = newValue.rawValue
                applyLanguage(newValue)
            }
        )
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.shared.log("Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)", level: .error)
            launchAtLogin = !enabled
        }
    }

    private func applyLanguage(_ language: AppLanguage) {
        AppLanguagePreferences.apply(language)
        appState.settingsNeedLanguageRestart = language != appState.languageAtLaunch
    }

    private func relaunchApp() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            NSApp.terminate(nil)
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundleURL.path]

        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            Logger.shared.log("Failed to relaunch Sift: \(error.localizedDescription)", level: .error)
        }
    }
}

// MARK: - Cleaning

struct CleaningSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("settings.cleaning.skipHiddenFiles") private var skipHiddenFiles = true
    @AppStorage("settings.cleaning.largeFileThreshold") private var largeFileThresholdMB: Int = 100
    @AppStorage("settings.cleaning.oldFileMonths") private var oldFileMonths: Int = 12
    @AppStorage(AppState.confirmBeforeDeleteKey) private var confirmBeforeDelete = true
    @AppStorage(ScanEngine.treatICloudPlaceholdersAsFilesKey) private var treatICloudPlaceholdersAsFiles = false

    private static let excludedFoldersKey = "settings.cleaning.largeFileExcludedFolders"
    @State private var excludedFolders: [String] = []

    var body: some View {
        SiftSettingsLabel(title: Text("Large file sweep"))
        SiftSettingsGroup {
            SiftSettingsRow(Text("Flag files larger than"), detail: Text("Older files over 10 MB are also flagged")) {
                HStack(spacing: 14) {
                    SiftSlider(value: thresholdBinding, range: 10...1000, step: 10)
                        .frame(minWidth: 140, maxWidth: 320)
                        .accessibilityLabel(Text("Flag files larger than"))
                    SiftValueBox(value: "\(largeFileThresholdMB)", unit: Text("MB"))
                        .accessibilityHidden(true)
                }
            }
            SiftSettingsDivider()
            SiftSettingsRow(Text("Count files as old after"), detail: Text("Untouched this long, a file over 10 MB is flagged")) {
                SiftStepper(value: $oldFileMonths, range: 1...60, unit: Text("months"))
            }
        }

        SiftSettingsLabel(title: Text("Safety"))
        SiftSettingsGroup {
            SiftSettingsToggleRow(Text("Skip hidden files"),
                                  detail: Text("Dotfiles stay out of the large file and installer sweeps"),
                                  isOn: $skipHiddenFiles)
            SiftSettingsDivider()
            SiftSettingsToggleRow(Text("Confirm before deleting"),
                                  detail: Text("The review sheet appears before anything is touched"),
                                  isOn: $confirmBeforeDelete)
            SiftSettingsDivider()
            SiftSettingsToggleRow(Text("Treat iCloud placeholders as files"),
                                  detail: Text("Off keeps bytes that were never downloaded out of the total"),
                                  isOn: $treatICloudPlaceholdersAsFiles)
        }

        SiftSettingsLabel(title: Text("Excluded folders"), note: Text("Never scanned"))
        SiftSettingsGroup {
            SiftFlowLayout {
                ForEach(excludedFolders, id: \.self) { folder in
                    SiftPathChip(path: folder, removeLabel: Text("Remove from exclusions")) {
                        removeExcludedFolder(folder)
                    }
                }
                SiftDashedAddButton(title: Text("Add folder")) { addExcludedFolder() }
            }
            .padding(14)
        }

        SiftSettingsLabel(title: Text("Cleanup exclusions"), note: Text("Right-click a cleanup result to exclude it"))
        SiftSettingsGroup {
            if appState.excludedCleanupPaths.isEmpty {
                SiftSettingsRow(Text("No excluded paths"),
                                detail: Text("Excluded paths and folders containing them stay out of manual and scheduled cleanup."))
            } else {
                SiftFlowLayout {
                    ForEach(appState.excludedCleanupPaths, id: \.self) { path in
                        SiftPathChip(path: path, removeLabel: Text("Remove")) {
                            appState.removeCleanupExclusion(path)
                        }
                        .disabled(appState.scanState.isActive)
                    }
                }
                .padding(14)
            }
        }

        SiftSettingsLabel(title: Text("Leftovers"))
        SiftSettingsGroup {
            // Read the live count directly (it's a UserDefaults-backed
            // computed property on AppState) so it stays correct when
            // orphans are ignored from the Leftovers view while this page is
            // open. AppState fires objectWillChange on both ignore (via
            // @Published orphanedFiles) and clear, re-rendering this.
            SiftSettingsRow(Text("Ignored leftovers"), detail: Text("Ignored files won't appear in future orphan scans.")) {
                HStack(spacing: 12) {
                    Text(verbatim: "\(appState.ignoredOrphanCount)")
                        .font(.siftMono(13))
                        .foregroundStyle(SiftColor.textSecondary)
                    Button("Forget Ignored") { appState.clearIgnoredOrphans() }
                        .buttonStyle(.sift(.secondary, compact: true))
                        .disabled(appState.ignoredOrphanCount == 0)
                }
            }
        }
        .onAppear {
            excludedFolders = UserDefaults.standard.stringArray(forKey: Self.excludedFoldersKey) ?? []
        }
    }

    private var thresholdBinding: Binding<Double> {
        Binding(
            get: { Double(largeFileThresholdMB) },
            set: { largeFileThresholdMB = Int($0) }
        )
    }

    private func persistExcludedFolders() {
        UserDefaults.standard.set(excludedFolders, forKey: Self.excludedFoldersKey)
    }

    private func addExcludedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add Folder…")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !excludedFolders.contains(url.path) {
            excludedFolders.append(url.path)
        }
        persistExcludedFolders()
    }

    private func removeExcludedFolder(_ folder: String) {
        excludedFolders.removeAll { $0 == folder }
        persistExcludedFolders()
    }
}

// MARK: - Appearance

/// Theme and accent, side by side; stacked when the panel is narrow.
struct AppearanceAccentSettings: View {
    @EnvironmentObject private var theme: ThemeManager
    @ObservedObject private var accentStore = AccentStore.shared

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                appearanceColumn.frame(minWidth: 330)
                accentColumn.frame(minWidth: 330)
            }
            VStack(alignment: .leading, spacing: 14) {
                appearanceColumn
                accentColumn
            }
        }
    }

    private var appearanceColumn: some View {
        column(Text("Appearance")) {
            SiftSegmented(selection: $theme.appearance, options: [
                (value: AppearanceMode.dark, label: Text("Dark")),
                (value: AppearanceMode.light, label: Text("Light")),
                (value: AppearanceMode.system, label: Text("System"))
            ])
            .fixedSize()
            Text("Accent follows the brass palette across the whole app")
        }
    }

    private var accentColumn: some View {
        column(Text("Accent")) {
            SiftAccentPicker(selection: $accentStore.accent)
            Text("Brass is the shipped accent; everything else derives from it")
        }
    }

    private func column<Content: View>(_ title: Text, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SiftSettingsLabel(title: title)
            VStack(alignment: .leading, spacing: 12) { content() }
                .font(.sift(12))
                .foregroundStyle(SiftColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .siftSurface(.inset)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Schedule

struct ScheduleSettingsView: View {
    @ObservedObject var scheduler: SchedulerService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let minimumSizes: [Int64] = [10, 50, 100, 250, 500, 1024, 2048, 5120].map { $0 * 1024 * 1024 }

    var body: some View {
        SiftSettingsLabel(title: Text("Automatic scanning"))
        SiftSettingsGroup {
            SiftSettingsToggleRow(Text("Enable scheduled scanning"),
                                  detail: Text("Sift scans on its own while it is open or in the menu bar"),
                                  isOn: Binding(get: { scheduler.config.isEnabled }, set: { scheduler.toggleEnabled($0) }))
            if scheduler.config.isEnabled {
                SiftSettingsDivider()
                SiftSettingsRow(Text("Scan interval")) {
                    SiftDropdown(
                        selection: Binding(get: { scheduler.config.interval }, set: { scheduler.updateSchedule(interval: $0) }),
                        options: ScheduleInterval.allCases
                    ) { String(localized: String.LocalizationValue($0.rawValue)) }
                    .fixedSize()
                }
                if scheduler.config.interval == .weekly {
                    SiftSettingsDivider()
                    SiftSettingsRow(Text("Day and time"), detail: Text("Runs on the hour, local time")) {
                        HStack(spacing: 8) {
                            SiftDropdown(
                                selection: Binding(
                                    get: { scheduler.config.weekday },
                                    set: { scheduler.updateWeeklySchedule(weekday: $0, hour: scheduler.config.hour) }
                                ),
                                options: Array(1...7)
                            ) { weekday in
                                let symbols = Calendar.current.standaloneWeekdaySymbols
                                return symbols[min(max(weekday, 1), symbols.count) - 1]
                            }
                            .fixedSize()
                            .accessibilityLabel(Text("Day"))
                            SiftDropdown(
                                selection: Binding(
                                    get: { scheduler.config.hour },
                                    set: { scheduler.updateWeeklySchedule(weekday: scheduler.config.weekday, hour: $0) }
                                ),
                                options: Array(0...23),
                                title: Self.hourTitle
                            )
                            .fixedSize()
                            .accessibilityLabel(Text("Time"))
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : SiftMotion.snappy, value: scheduler.config.isEnabled)
        .animation(reduceMotion ? nil : SiftMotion.snappy, value: scheduler.config.interval)

        if scheduler.config.isEnabled {
            SiftSettingsLabel(title: Text("After each scan"))
            SiftSettingsGroup {
                SiftSettingsToggleRow(Text("Auto-clean after scan"),
                                      detail: Text("Permanently deletes the junk the scan selected, without asking"),
                                      isOn: $scheduler.config.autoClean)
                SiftSettingsDivider()
                SiftSettingsRow(Text("Minimum size"), detail: Text("Auto-clean skips scans that would free less than this")) {
                    SiftDropdown(selection: $scheduler.config.minimumCleanSize, options: minimumSizeOptions) {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory)
                    }
                    .fixedSize()
                    .disabled(!scheduler.config.autoClean)
                    .opacity(scheduler.config.autoClean ? 1 : 0.45)
                }
                SiftSettingsDivider()
                SiftSettingsToggleRow(Text("Notify on completion"),
                                      detail: Text("A notification with what was found or cleaned"),
                                      isOn: $scheduler.config.notifyOnCompletion)
            }

            SiftSettingsLabel(title: Text("Runs"))
            SiftSettingsGroup {
                SiftSettingsRow(Text("Last run")) { runValue(scheduler.config.formattedLastRun) }
                SiftSettingsDivider()
                SiftSettingsRow(Text("Next run")) { runValue(scheduler.config.formattedNextRun) }
            }
        }
    }

    private var minimumSizeOptions: [Int64] {
        let current = scheduler.config.minimumCleanSize
        return Self.minimumSizes.contains(current) ? Self.minimumSizes : (Self.minimumSizes + [current]).sorted()
    }

    private func runValue(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.siftMono(12))
            .foregroundStyle(SiftColor.textSecondary)
    }

    private static func hourTitle(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Permissions

struct PermissionsSettingsView: View {
    var presentation: PermissionCoordinator.Presentation = .mainWindow
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var permission = PermissionCoordinator.shared

    private static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    var body: some View {
        SiftSettingsLabel(title: Text("Full Disk Access"))
        SiftSettingsGroup {
            SiftSettingsRow(
                Text(LocalizedStringKey(appState.hasFullDiskAccess ? "Full access" : "Limited access")),
                detail: Text(LocalizedStringKey(appState.hasFullDiskAccess ? "Ready for protected locations" : "Some locations are unavailable"))
            ) {
                HStack(spacing: 8) {
                    SiftStatusPill(Text(appState.hasFullDiskAccess ? "On" : "Off"),
                                   tone: appState.hasFullDiskAccess ? .success : .warning)
                    Button("Check access") { refreshAccess() }
                        .buttonStyle(.sift(.secondary, compact: true))
                    if !appState.hasFullDiskAccess {
                        Button("Set up") {
                            permission.requestAccess(context: .general, presentation: presentation) { refreshAccess() }
                        }
                        .buttonStyle(.sift(.primary, compact: true))
                    }
                }
            }
        }

        SiftSettingsLabel(title: Text("Automation"), note: Text("macOS asks the first time"))
        SiftSettingsGroup {
            SiftSettingsRow(Text("Finder"),
                            detail: Text("Sift asks Finder to reveal files and to empty the Trash. Turn it on or off in Privacy & Security > Automation.")) {
                Button("Open Automation settings") { NSWorkspace.shared.open(Self.automationSettingsURL) }
                    .buttonStyle(.sift(.secondary, compact: true))
            }
        }
        .onAppear { refreshAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccess()
        }
    }

    private func refreshAccess() {
        appState.checkFullDiskAccess()
        permission.refreshStatus()
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private static let repositoryURL = URL(string: "https://github.com/BadryansahBangsawan/Sift")!
    private static let issuesURL = URL(string: "https://github.com/BadryansahBangsawan/Sift/issues")!

    var body: some View {
        SiftSettingsLabel(title: Text("About"), note: Text("MIT License"))
        SiftSettingsGroup {
            SiftSettingsRow(Text("Source code"), detail: Text("Free, open-source macOS app manager.")) {
                Button("GitHub Repository") { NSWorkspace.shared.open(Self.repositoryURL) }
                    .buttonStyle(.sift(.secondary, compact: true))
            }
            SiftSettingsDivider()
            SiftSettingsRow(Text("Found a problem?"), detail: Text("Issues are tracked on GitHub")) {
                Button("Report an Issue") { NSWorkspace.shared.open(Self.issuesURL) }
                    .buttonStyle(.sift(.secondary, compact: true))
            }
        }
    }
}
