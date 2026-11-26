import SwiftUI

/// Settings → Updates. Sparkle owns the download/verify/install flow; this
/// page only shows the version and hands the two automatic-update settings
/// through to the app-owned updater.
struct AppUpdateSettingsView: View {
    @EnvironmentObject private var updates: AppUpdateController

    var body: some View {
        SiftSettingsLabel(title: Text("Version"))
        SiftSettingsGroup {
            SiftSettingsRow(
                Text("Version"),
                detail: Text(verbatim: "\(AppVersion.marketing) (\(AppVersion.build))")
            ) {
                Button("Check for Updates…") { updates.checkForUpdates() }
                    .buttonStyle(.sift(.primary, compact: true))
                    .disabled(!updates.canCheckForUpdates)
                    .accessibilityIdentifier("settings.checkForUpdates")
            }
        }

        SiftSettingsLabel(title: Text("Updates"))
        SiftSettingsGroup {
            SiftSettingsToggleRow(
                Text("Check for updates automatically"),
                isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.automaticallyChecksForUpdates = $0 }
                )
            )
            .accessibilityIdentifier("settings.automaticChecks")
            SiftSettingsDivider()
            SiftSettingsToggleRow(
                Text("Download and install updates automatically"),
                isOn: Binding(
                    get: { updates.automaticallyDownloadsUpdates },
                    set: { updates.automaticallyDownloadsUpdates = $0 }
                )
            )
            .disabled(!updates.canAutomaticallyDownloadUpdates)
            .accessibilityIdentifier("settings.automaticDownloads")
        }
    }
}
