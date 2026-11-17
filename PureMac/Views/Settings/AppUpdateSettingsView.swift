import AppKit
import SwiftUI

struct AppUpdateSettingsView: View {
    @ObservedObject private var updater = UpdateService.shared
    @AppStorage("settings.updates.installationMethod") private var installationMethod = "download"

    private static let brewCommand = "brew update && brew upgrade --cask puremac"

    var body: some View {
        SiftSettingsLabel(title: Text("Version"))
        SiftSettingsGroup {
            SiftSettingsRow(
                Text("Keep Sift up to date"),
                detail: Text("Version \(UpdateService.installedVersion) (\(UpdateService.installedBuild)). Checks the official app releases on GitHub.")
            ) {
                HStack(spacing: 10) {
                    if updater.isChecking { ProgressView().controlSize(.small) }
                    Button("Check for Updates") { updater.checkForUpdates() }
                        .buttonStyle(.sift(.primary, compact: true))
                        .disabled(updater.isChecking)
                        .accessibilityIdentifier("settings.checkForUpdates")
                }
            }
            if updater.state != .idle {
                SiftSettingsDivider()
                status
            }
            if let checked = updater.lastChecked {
                SiftSettingsDivider()
                SiftSettingsRow(Text("Last checked")) {
                    Text(verbatim: checked.formatted(date: .abbreviated, time: .shortened))
                        .font(.siftMono(12))
                        .foregroundStyle(SiftColor.textSecondary)
                }
            }
        }

        SiftSettingsLabel(title: Text("Installing updates"))
        SiftSettingsGroup {
            SiftSettingsRow(Text("Update method"), detail: methodDetail) {
                SiftSegmented(selection: $installationMethod, options: [
                    (value: "download", label: Text("Download (DMG / ZIP)")),
                    (value: "homebrew", label: Text("Homebrew"))
                ])
                .fixedSize()
            }
            if installationMethod == "homebrew" {
                SiftSettingsDivider()
                HStack(spacing: 12) {
                    Text(verbatim: Self.brewCommand)
                        .font(.siftMono(11.5))
                        .foregroundStyle(SiftColor.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SiftColor.window))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(SiftColor.controlStroke, lineWidth: 1))
                    Button("Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.brewCommand, forType: .string)
                    }
                    .buttonStyle(.sift(.secondary, compact: true))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
            SiftSettingsDivider()
            SiftSettingsRow(Text("Release notes"), detail: Text("Every version and what changed, on GitHub")) {
                Button("View releases") { NSWorkspace.shared.open(UpdateService.releasesURL) }
                    .buttonStyle(.sift(.secondary, compact: true))
            }
        }
    }

    private var methodDetail: Text {
        installationMethod == "homebrew"
            ? Text("To update with Homebrew, run this command in Terminal. The cask may follow the GitHub release a little later.")
            : Text("Download the new app from the release page, quit Sift, then replace it in Applications.")
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            statusRow(.refresh, tone: .neutral, title: Text("Checking for updates…"))
        case .available(let release):
            statusRow(.arrowDown, tone: .accent, title: Text(String(format: String(localized: "Sift %@ is available"), release.tagName))) {
                Button("Open release page") { NSWorkspace.shared.open(release.htmlURL) }
                    .buttonStyle(.sift(.secondary, compact: true))
            }
        case .upToDate:
            statusRow(.check, tone: .success, title: Text("You're using the latest available version of Sift."))
        case .failed(let message):
            statusRow(.triangleAlert, tone: .warning, title: Text("Couldn't check for updates"), detail: Text(verbatim: message))
        }
    }

    private func statusRow(_ icon: SiftIcon, tone: SiftTone, title: Text, detail: Text? = nil) -> some View {
        statusRow(icon, tone: tone, title: title, detail: detail) { EmptyView() }
    }

    private func statusRow<Control: View>(_ icon: SiftIcon, tone: SiftTone, title: Text, detail: Text? = nil,
                                          @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            SiftIconTile(icon: icon, tone: tone, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                title.font(.sift(13, weight: 500)).foregroundStyle(tone == .neutral ? SiftColor.textPrimary : tone.foreground)
                if let detail {
                    detail.font(.sift(12)).foregroundStyle(SiftColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
