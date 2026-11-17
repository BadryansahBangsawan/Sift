import SwiftUI

/// Full Disk Access prompt that replaces the bare permission-denied alert.
/// Auto-polls FDA state, auto-retries the failed operation on grant, and
/// offers escape hatches for the "Sift isn't in the list" case.
struct PermissionSheet: View {
    @ObservedObject private var coordinator = PermissionCoordinator.shared
    @State private var appeared = false
    @State private var pulse = false
    @State private var showAdvanced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            body_
            divider
            footer
        }
        .frame(width: 560)
        .background(SiftColor.card)
        .animation(reduceMotion ? nil : SiftMotion.snappy, value: coordinator.hasFullDiskAccess)
        .onAppear {
            if reduceMotion {
                appeared = true
                return
            }
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(SiftColor.stroke).frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            SiftIconTile(
                icon: coordinator.hasFullDiskAccess ? .shieldCheck : .lockKeyhole,
                tone: coordinator.hasFullDiskAccess ? .success : .accent,
                size: 40
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(coordinator.context.headline)
                    .font(.siftDisplay(24))
                    .tracking(-0.4)
                    .foregroundStyle(SiftColor.textPrimary)
                Text(LocalizedStringKey(
                    coordinator.hasFullDiskAccess
                        ? "Access granted. Retrying…"
                        : "1-tap setup. We'll detect the change automatically."
                ))
                    .siftStyle(.label)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Body

    @ViewBuilder
    private var body_: some View {
        if coordinator.hasFullDiskAccess {
            grantedBody
                .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
        } else {
            requestBody
                .transition(.opacity)
        }
    }

    private var requestBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Two paths the user can choose between: drag the Sift bundle
            // straight into the FDA list, OR have us reveal it in Finder so
            // they can drag from there. Drag-from-our-sheet is faster but
            // some users will still prefer the Finder flow they recognize.
            HStack(alignment: .center, spacing: 16) {
                AppBundleDragHandle()

                Rectangle().fill(SiftColor.stroke).frame(width: 1, height: 96)

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        Haptics.tap()
                        coordinator.openSettingsAndReveal()
                    } label: {
                        Label {
                            Text("Open Settings & reveal Sift")
                        } icon: {
                            SiftIcon.settings.image(15)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.siftPrimary)
                    .keyboardShortcut(.defaultAction)

                    Text("Or drag the icon on the left straight into Settings.")
                        .font(.sift(11.5))
                        .foregroundStyle(SiftColor.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }

            // Step-by-step strip: a real sequence, so it is numbered.
            HStack(alignment: .top, spacing: 0) {
                stepCell(number: 1, title: "Turn on Sift",
                         caption: "Toggle the row that appears.")
                stepDivider
                stepCell(number: 2, title: "Authenticate",
                         caption: "Touch ID or password.")
                stepDivider
                stepCell(number: 3, title: "Done",
                         caption: "We auto-retry — no need to come back.")
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous).fill(SiftColor.control))
            .overlay(
                RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous)
                    .strokeBorder(SiftColor.controlStroke, lineWidth: 1)
            )

            // Listening indicator
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(SiftColor.accent.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(SiftColor.accent)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 1.4 : 0.8)
                        .opacity(pulse ? 0.4 : 1)
                }
                .accessibilityHidden(true)
                Text("Watching for permission change…")
                    .font(.sift(12))
                    .foregroundStyle(SiftColor.textSecondary)
                Spacer()
                Button(LocalizedStringKey(showAdvanced ? "Hide help" : "Sift not in the list?")) {
                    withAnimation(SiftMotion.snappy) { showAdvanced.toggle() }
                }
                .buttonStyle(.siftQuiet)
            }

            if showAdvanced {
                advancedPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !coordinator.failedItemPaths.isEmpty {
                blockedList
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .opacity(appeared ? 1 : 0)
    }

    private var advancedPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try this if Sift doesn't appear:")
                .font(.sift(12, weight: 500))
                .foregroundStyle(SiftColor.textSecondary)

            HStack(spacing: 8) {
                advancedButton(
                    icon: .folderOpen,
                    title: "Reveal app",
                    subtitle: "Drag Sift.app into the list"
                ) {
                    FullDiskAccessManager.shared.revealAppInFinder()
                }
                advancedButton(
                    icon: .rotateCw,
                    title: "Reset + reprompt",
                    subtitle: "Clear stale TCC entry"
                ) {
                    coordinator.resetAndReprime()
                }
            }
        }
        .siftSurface(.inset, padding: 14)
    }

    private func advancedButton(icon: SiftIcon, title: LocalizedStringKey,
                                subtitle: LocalizedStringKey,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SiftIconTile(icon: icon, tone: .warning, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.sift(12.5, weight: 500))
                        .foregroundStyle(SiftColor.textPrimary)
                    Text(subtitle)
                        .font(.sift(11))
                        .foregroundStyle(SiftColor.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .siftRowBackground()
            .background(RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous).fill(SiftColor.card))
        }
        .buttonStyle(.plain)
    }

    private var blockedList: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(coordinator.failedItemPaths.prefix(6), id: \.self) { path in
                    Text(path)
                        .siftStyle(.monoSmall)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if coordinator.failedItemPaths.count > 6 {
                    Text(remainingText(coordinator.failedItemPaths.count - 6))
                        .font(.sift(11))
                        .foregroundStyle(SiftColor.textTertiary)
                }
            }
            .padding(.top, 4)
        } label: {
            Text(blockedHeaderText(coordinator.failedItemPaths.count))
                .font(.sift(12, weight: 500))
                .foregroundStyle(SiftColor.textSecondary)
        }
        .tint(SiftColor.textTertiary)
    }

    private func remainingText(_ count: Int) -> String {
        String(format: String(localized: "+ %lld more"), Int64(count))
    }

    private func blockedHeaderText(_ count: Int) -> String {
        String(
            format: String(localized: "%lld blocked path(s)"),
            Int64(count)
        )
    }

    private func stepCell(number: Int, title: LocalizedStringKey,
                          caption: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(number)")
                .font(.siftMono(10.5, weight: 600))
                .foregroundStyle(SiftColor.onAccent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(SiftColor.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.sift(12, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                Text(caption)
                    .font(.sift(10.5))
                    .foregroundStyle(SiftColor.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepDivider: some View {
        Rectangle()
            .fill(SiftColor.controlStroke)
            .frame(width: 1)
            .padding(.vertical, 8)
    }

    private var grantedBody: some View {
        VStack(spacing: 10) {
            SiftIconTile(icon: .check, tone: .success, size: 64)
            Text("Access granted")
                .font(.siftDisplay(24))
                .tracking(-0.4)
                .foregroundStyle(SiftColor.textPrimary)
            Text("Retrying the operation now.")
                .siftStyle(.label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Skip for now") {
                coordinator.dismiss(callRetry: false)
            }
            .buttonStyle(.siftQuiet)

            Spacer()

            if !coordinator.hasFullDiskAccess {
                Button("I granted it — retry") {
                    coordinator.refreshStatus()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        if coordinator.hasFullDiskAccess {
                            coordinator.dismiss(callRetry: true)
                        }
                    }
                }
                .buttonStyle(.siftSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(SiftColor.rail)
    }
}
