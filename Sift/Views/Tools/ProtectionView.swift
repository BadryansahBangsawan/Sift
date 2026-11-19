import AppKit
import SwiftUI

struct ProtectionView: View {
    private enum Phase {
        case idle
        case running
        case complete(ProtectionSnapshot)
    }

    private let audit: ProtectionAudit
    @State private var phase: Phase = .idle
    @State private var auditTask: Task<Void, Never>?

    init(audit: ProtectionAudit = ProtectionAudit()) {
        self.audit = audit
    }

    var body: some View {
        VStack(spacing: SiftSpacing.gutter) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: SiftSpacing.gutter) {
                    auditContent
                    HStack(alignment: .top, spacing: SiftSpacing.gutter) {
                        permissionsCard
                        browserPrivacyCard
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Protection")
        .onDisappear {
            auditTask?.cancel()
            auditTask = nil
            if case .running = phase {
                phase = .idle
            }
        }
    }

    private var header: some View {
        SiftToolHeader(
            Text("Protection"),
            eyebrow: Text("Tools"),
            subtitle: Text("Review the macOS safeguards that protect apps, disks, network access, and system files.")
        ) {
            Button(action: runAudit) {
                HStack(spacing: 8) {
                    if case .running = phase {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        SiftIcon.shieldCheck.image(15)
                    }
                    Text(auditButtonTitle)
                }
            }
            .buttonStyle(.siftPrimary)
            .disabled(isRunning)
            .accessibilityLabel(auditButtonTitle)
        }
    }

    @ViewBuilder
    private var auditContent: some View {
        switch phase {
        case .idle:
            HStack(spacing: 16) {
                SiftIconTile(icon: .shieldCheck, tone: .accent, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check built-in safeguards")
                        .font(.sift(16, weight: 500))
                        .foregroundStyle(SiftColor.textPrimary)
                    Text("The audit reads current settings and does not change your Mac. It is a configuration review, not a malware scan.")
                        .siftStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .siftSurface(.card)
        case .running:
            safeguardsCard {
                ForEach(Array(ProtectionCheck.allCases.enumerated()), id: \.element.id) { index, check in
                    HStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: SiftRadius.tile, style: .continuous).fill(SiftColor.control))
                        Text(check.title)
                            .font(.sift(13.5, weight: 500))
                            .foregroundStyle(SiftColor.textPrimary)
                        Spacer()
                        Text("Checking")
                            .siftStyle(.label)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)

                    if index < ProtectionCheck.allCases.count - 1 {
                        SiftRowDivider()
                    }
                }
            } footer: {
                EmptyView()
            }
        case .complete(let snapshot):
            safeguardsCard {
                ForEach(Array(snapshot.findings.enumerated()), id: \.element.id) { index, finding in
                    ProtectionFindingRow(finding: finding)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)

                    if index < snapshot.findings.count - 1 {
                        SiftRowDivider()
                    }
                }
            } footer: {
                SiftFootnote(
                    Text("Checked \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened)). Unknown means the setting could not be confirmed.")
                )
            }
        }
    }

    /// A card holding the safeguard rows as one inset group, like the Settings groups.
    private func safeguardsCard<Rows: View, Footer: View>(
        @ViewBuilder rows: () -> Rows,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                rows()
            }
            .siftSurface(.inset, padding: 0)
            footer()
        }
        .siftSurface(.card)
    }

    private var permissionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SiftIconTile(icon: .lockKeyhole, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("App permissions")
                        .siftStyle(.cardTitle)
                    Text("Review which apps can access private data and hardware.")
                        .siftStyle(.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                SettingsButton(title: "Full Disk Access", icon: "externaldrive.badge.person.crop") {
                    ProtectionNavigation.openSettings("com.apple.preference.security?Privacy_AllFiles")
                }
                SettingsButton(title: "Location", icon: "location") {
                    ProtectionNavigation.openSettings("com.apple.preference.security?Privacy_LocationServices")
                }
                SettingsButton(title: "Camera", icon: "video") {
                    ProtectionNavigation.openSettings("com.apple.preference.security?Privacy_Camera")
                }
                SettingsButton(title: "Microphone", icon: "mic") {
                    ProtectionNavigation.openSettings("com.apple.preference.security?Privacy_Microphone")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface(.card)
    }

    private var browserPrivacyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SiftIconTile(icon: .globe, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Browser privacy")
                        .siftStyle(.cardTitle)
                    Text("Browser controls must be reviewed inside each browser. Sift does not change cookies, history, site permissions, or extensions.")
                        .siftStyle(.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Link(destination: URL(string: "https://support.apple.com/guide/safari/sfri35610/mac")!) {
                    Label {
                        Text("Safari privacy guide")
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                }
                Link(destination: URL(string: "https://support.google.com/chrome/answer/17561599?hl=en")!) {
                    Label {
                        Text("Chrome privacy guide")
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                }
            }
            .buttonStyle(.sift(.secondary, compact: true))

            Text("Safari: Settings > Privacy")
                .siftStyle(.mono)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .siftSurface(.card)
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    private var auditButtonTitle: String {
        switch phase {
        case .idle:
            return String(localized: "Run audit")
        case .running:
            return String(localized: "Checking")
        case .complete:
            return String(localized: "Check again")
        }
    }

    private func runAudit() {
        guard !isRunning else { return }
        auditTask?.cancel()
        phase = .running
        auditTask = Task {
            let snapshot = await audit.run()
            guard !Task.isCancelled else { return }
            withAnimation(SiftMotion.snappy) {
                phase = .complete(snapshot)
            }
            auditTask = nil
        }
    }
}

private struct ProtectionFindingRow: View {
    let finding: ProtectionFinding

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SiftIconTile(icon: finding.status.icon, tone: finding.status.tone)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(finding.check.title)
                        .font(.sift(13.5, weight: 500))
                        .foregroundStyle(SiftColor.textPrimary)
                    SiftStatusPill(
                        Text(verbatim: finding.status.label(for: finding.check)),
                        tone: finding.status.tone
                    )
                    if let version = finding.version {
                        Text(version)
                            .siftStyle(.monoSmall)
                    }
                }
                Text(finding.detail)
                    .siftStyle(.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(finding.check.actionTitle) {
                ProtectionNavigation.openAction(for: finding.check)
            }
            .buttonStyle(.sift(.secondary, compact: true))
        }
    }
}

private struct SettingsButton: View {
    let title: LocalizedStringKey
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.sift(.secondary, compact: true))
    }
}

private enum ProtectionNavigation {
    static func openAction(for check: ProtectionCheck) {
        switch check {
        case .gatekeeper:
            openSettings("com.apple.preference.security")
        case .fileVault:
            openSettings("com.apple.preference.security?FileVault")
        case .firewall:
            openSettings("com.apple.Network-Settings.extension?Firewall")
        case .systemIntegrityProtection:
            openWeb("https://support.apple.com/guide/security/secb7ea06b49/web")
        case .xProtect:
            openSettings("com.apple.Software-Update-Settings.extension")
        }
    }

    static func openSettings(_ destination: String) {
        openWeb("x-apple.systempreferences:\(destination)")
    }

    private static func openWeb(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

private extension ProtectionCheck {
    var title: String {
        switch self {
        case .gatekeeper:
            return String(localized: "Gatekeeper")
        case .fileVault:
            return String(localized: "FileVault")
        case .firewall:
            return String(localized: "Application Firewall")
        case .systemIntegrityProtection:
            return String(localized: "System Integrity Protection")
        case .xProtect:
            return String(localized: "XProtect")
        }
    }

    var actionTitle: String {
        switch self {
        case .gatekeeper:
            return String(localized: "Security Settings")
        case .fileVault:
            return String(localized: "FileVault Settings")
        case .firewall:
            return String(localized: "Firewall Settings")
        case .systemIntegrityProtection:
            return String(localized: "Apple Guide")
        case .xProtect:
            return String(localized: "Software Update")
        }
    }
}

private extension ProtectionStatus {
    var icon: SiftIcon {
        switch self {
        case .enabled:
            return .shieldCheck
        case .disabled:
            return .triangleAlert
        case .unknown:
            return .info
        }
    }

    var tone: SiftTone {
        switch self {
        case .enabled:
            return .success
        case .disabled:
            return .warning
        case .unknown:
            return .neutral
        }
    }

    func label(for check: ProtectionCheck) -> String {
        switch (self, check) {
        case (.enabled, .xProtect):
            return String(localized: "Installed")
        case (.enabled, _):
            return String(localized: "On")
        case (.disabled, _):
            return String(localized: "Off")
        case (.unknown, _):
            return String(localized: "Unknown")
        }
    }
}
