import SwiftUI

/// First-launch flow. Four scenes, large typography, plenty of breathing
/// room. Sequence is welcome → mission → permission (with live demo) →
/// ready. Skip is always available — we don't want to gate adoption on a
/// reluctant user, but we do want to make the FDA step concrete enough that
/// the people who *want* to grant it understand exactly what they're doing.
struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var page: Page = .welcome
    @State private var hasFda = false
    @State private var hasOpenedSettings = false
    @State private var autoAdvanceScheduled = false
    /// +1 when navigating forward, -1 going back — drives the slide direction
    /// so Back doesn't slide the wrong way.
    @State private var direction: Int = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pollTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    enum Page: Int, CaseIterable {
        case welcome, mission, permission, ready

        var index: Int { rawValue }
        static var count: Int { allCases.count }
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(x: direction >= 0 ? 48 : -48)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98)),
            removal: .offset(x: direction >= 0 ? -48 : 48)
                .combined(with: .opacity)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SiftWordmark()
                Spacer()
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 32)
            .padding(.top, 44)

            content
                .frame(maxWidth: 620, maxHeight: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .id(page)
                .transition(pageTransition)

            bottomBar
        }
        .frame(minWidth: 680, idealWidth: 680, maxWidth: .infinity, minHeight: 560, idealHeight: 560, maxHeight: .infinity)
        .background(SiftColor.window.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .tint(SiftColor.accent)
        .onAppear {
            FullDiskAccessManager.shared.triggerRegistration()
            refreshFda()
        }
        .onReceive(pollTimer) { _ in
            if page == .permission { refreshFda() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .welcome: WelcomeScene()
        case .mission: MissionScene()
        case .permission: PermissionScene(
            hasFda: hasFda,
            hasOpenedSettings: hasOpenedSettings,
            openSettings: openSettings,
            revealAppInFinder: { FullDiskAccessManager.shared.revealAppInFinder() }
        )
        case .ready: ReadyScene(hasFda: hasFda)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            if page != .welcome {
                Button("Back") { advance(by: -1) }
                    .buttonStyle(.sift(.quiet))
            } else {
                Button("Skip") { isComplete = true }
                    .buttonStyle(.sift(.quiet))
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(Page.allCases, id: \.self) { p in
                    Capsule()
                        .fill(p == page ? SiftColor.accent : SiftColor.track)
                        .frame(width: p == page ? 20 : 6, height: 6)
                        .animation(reduceMotion ? nil : SiftMotion.snappy, value: page)
                }
            }
            .accessibilityHidden(true)

            Spacer()

            if page == .ready {
                Button("Start") { isComplete = true }
                    .buttonStyle(.siftPrimary)
            } else {
                // On the permission page the Settings button is the main action.
                Button(LocalizedStringKey(page == .permission ? "Continue" : "Next")) { advance(by: 1) }
                    .buttonStyle(page == .permission ? .siftSecondary : .siftPrimary)
            }
        }
        .frame(maxWidth: 620)
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    // MARK: - Actions

    private func advance(by delta: Int) {
        let target = max(0, min(Page.count - 1, page.index + delta))
        guard target != page.index else { return }
        Haptics.tap()
        // Direction must be set BEFORE the transaction so the transition
        // resolves with the correct slide edge.
        direction = delta >= 0 ? 1 : -1
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) {
            page = Page(rawValue: target) ?? page
        }
    }

    private func openSettings() {
        FullDiskAccessManager.shared.openFullDiskAccessSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            FullDiskAccessManager.shared.revealAppInFinder()
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            hasOpenedSettings = true
        }
    }

    private func refreshFda() {
        let granted = FullDiskAccessManager.shared.hasFullDiskAccess
        if granted != hasFda {
            withAnimation(.easeInOut(duration: 0.3)) {
                hasFda = granted
            }
            if granted { Haptics.success() }
        }
        // Auto-advance once they grant access while on the permission page.
        // The autoAdvanceScheduled latch prevents the 1-second poll from
        // queueing multiple .8s delays if grants are detected on back-to-back
        // ticks before the page actually flips.
        guard granted, page == .permission, !autoAdvanceScheduled else { return }
        autoAdvanceScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            // Re-check page in case the user manually advanced or backed up
            // during the delay window.
            guard page == .permission else {
                autoAdvanceScheduled = false
                return
            }
            advance(by: 1)
            autoAdvanceScheduled = false
        }
    }
}

// MARK: - Scenes

private struct WelcomeScene: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 14) {
                Text("Reclaim your Mac")
                    .siftStyle(.hero)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Apple sells you small disks. We help you keep them clean.")
                    .font(.sift(15))
                    .foregroundStyle(SiftColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Free. Open source. MIT licensed.")
                    .siftStyle(.label)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .siftSurface(.hero)
            Spacer(minLength: 0)
        }
    }
}

private struct MissionScene: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("What's inside")
                    .siftStyle(.pageTitle)
                Text("Three things, done well.")
                    .siftStyle(.body)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                FeatureRow(
                    icon: .sparkles,
                    title: "Smart Scan",
                    body: "Find caches, logs, broken installs, and the AI-app history hiding in your library."
                )
                rowDivider
                FeatureRow(
                    icon: .packageMinus,
                    title: "App Uninstaller",
                    body: "Drag an app, see every file it dropped, remove all of it. No leftovers."
                )
                rowDivider
                FeatureRow(
                    icon: .file,
                    title: "Orphan Finder",
                    body: "Surfaces files that outlived the apps that created them."
                )
            }
            .siftSurface(.card, padding: 0)

            Spacer(minLength: 0)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(SiftColor.stroke).frame(height: 1).padding(.horizontal, 18)
    }
}

private struct FeatureRow: View {
    let icon: SiftIcon
    let title: LocalizedStringKey
    let body_: LocalizedStringKey

    init(icon: SiftIcon, title: LocalizedStringKey, body: LocalizedStringKey) {
        self.icon = icon
        self.title = title
        self.body_ = body
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SiftIconTile(icon: icon, tone: .accent, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.sift(13.5, weight: 500))
                    .foregroundStyle(SiftColor.textPrimary)
                Text(body_)
                    .font(.sift(12))
                    .foregroundStyle(SiftColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionScene: View {
    let hasFda: Bool
    let hasOpenedSettings: Bool
    let openSettings: () -> Void
    let revealAppInFinder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer(minLength: 0)

            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(hasFda ? "Permission granted" : "One permission, then we're done"))
                        .siftStyle(.metricSmall)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(LocalizedStringKey(
                        hasFda
                            ? "Sift can now reach the locations macOS protects by default."
                            : "macOS hides certain folders from every app until you say otherwise. We need them to find caches and uninstall cleanly."
                    ))
                        .siftStyle(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)

                FDADemoView()
                    .frame(width: 290)
            }

            if hasFda {
                SiftNoticeBanner(
                    Text("All set — moving you to the next step."),
                    icon: .check,
                    tone: .success
                )
                .transition(.opacity.combined(with: .scale))
            } else {
                // Two equally legitimate paths: open Settings and have it
                // reveal Sift in Finder, OR grab the draggable icon on the
                // left and drop it directly into the FDA list.
                HStack(alignment: .center, spacing: 18) {
                    AppBundleDragHandle()

                    Rectangle().fill(SiftColor.stroke).frame(width: 1, height: 96)

                    VStack(spacing: 10) {
                        Button {
                            openSettings()
                        } label: {
                            Label {
                                Text(LocalizedStringKey(hasOpenedSettings ? "Reopen Settings" : "Open Settings & reveal Sift"))
                            } icon: {
                                SiftIcon.settings.image(15)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.siftPrimary)
                        .keyboardShortcut(.defaultAction)

                        if hasOpenedSettings {
                            HStack(spacing: 4) {
                                Button("Reveal app again") { revealAppInFinder() }
                                Button("Reset permissions") {
                                    _ = FullDiskAccessManager.shared.resetFullDiskAccess()
                                    FullDiskAccessManager.shared.triggerRegistration()
                                }
                            }
                            .buttonStyle(.siftQuiet)
                            .transition(.opacity)
                        } else {
                            Text("Tip: drag the icon on the left straight into the list.")
                                .font(.sift(11.5))
                                .foregroundStyle(SiftColor.textTertiary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity)
                }
                .siftSurface(.card, padding: 12)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ReadyScene: View {
    let hasFda: Bool
    @State private var bounce = false
    @State private var fireConfetti = false
    @State private var confettiWork: DispatchWorkItem?
    @AppStorage("PureMac.HasSeenWelcomeConfetti") private var hasSeenConfetti = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Confetti sits above the content but behind any touch targets;
            // disabling hit-testing keeps the Start button clickable through
            // falling particles.
            if !hasSeenConfetti {
                ConfettiView(trigger: fireConfetti)
                    .allowsHitTesting(false)
            }

            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 18) {
                    SiftIconTile(icon: hasFda ? .check : .lockKeyhole, tone: hasFda ? .success : .warning, size: 56)
                        .scaleEffect(bounce || reduceMotion ? 1.0 : 0.85)
                        .onAppear {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) {
                                bounce = true
                            }
                            // Fire the welcome confetti exactly once per install.
                            // The work item is cancelled in onDisappear so a fast
                            // user who clicks Start within the 0.35s delay doesn't
                            // burn the once-per-install flag without ever seeing the
                            // celebration.
                            guard !hasSeenConfetti else { return }
                            let work = DispatchWorkItem {
                                fireConfetti = true
                                hasSeenConfetti = true
                                Haptics.success()
                            }
                            confettiWork = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
                        }
                        .onDisappear {
                            confettiWork?.cancel()
                            confettiWork = nil
                        }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(LocalizedStringKey(hasFda ? "You're ready" : "Ready when you are"))
                            .siftStyle(.hero)
                        Text(LocalizedStringKey(
                            hasFda
                                ? "Hit Start to run your first Smart Scan."
                                : "Some features will be limited without Full Disk Access. You can grant it later in Settings."
                        ))
                            .font(.sift(14))
                            .foregroundStyle(SiftColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .siftSurface(.hero)

                Spacer(minLength: 0)
            }
        }
    }
}
