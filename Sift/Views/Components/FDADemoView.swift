import SwiftUI

/// A short looping illustration of what the user is about to do in the real
/// System Settings pane. Built entirely in SwiftUI — no GIFs, no video, no
/// external assets. The point is to make the FDA step feel concrete so the
/// user knows exactly which toggle to flip before they even open Settings.
///
/// Frames cycle every ~5 seconds: idle → row highlights → toggle flips →
/// green check appears → hold → reset.
struct FDADemoView: View {
    enum Frame: Int, CaseIterable {
        case idle
        case highlight
        case toggleOn
        case granted
        case hold
    }

    @State private var frame: Frame = .idle
    @State private var isActive = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [DemoRow] {
        [
            DemoRow(name: "Finder", systemImage: "macwindow", granted: true),
            DemoRow(name: "Sift", systemImage: "sparkles",
                    granted: frame == .toggleOn || frame == .granted || frame == .hold,
                    isPureMac: true),
            DemoRow(name: "Terminal", systemImage: "terminal", granted: true),
        ]
    }

    var body: some View {
        VStack(spacing: 14) {
            settingsCard

            HStack(spacing: 6) {
                SiftIcon.lockKeyhole.image(12)
                Text("Privacy & Security → Full Disk Access")
                    .font(.sift(11.5))
            }
            .foregroundStyle(SiftColor.textTertiary)
        }
        .onAppear {
            // Reduce Motion: freeze on the end state — the user sees the
            // "toggled on, granted" frame as a static illustration instead
            // of an infinite loop.
            if reduceMotion {
                frame = .hold
                return
            }
            isActive = true
            cycle()
        }
        .onDisappear { isActive = false }
    }

    // MARK: - Settings card

    private var settingsCard: some View {
        VStack(spacing: 0) {
            // Faux titlebar
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(SiftColor.faint).frame(width: 9, height: 9)
                }
                Spacer()
                Text("Full Disk Access")
                    .font(.sift(11.5, weight: 500))
                    .foregroundStyle(SiftColor.textSecondary)
                Spacer()
                Color.clear.frame(width: 39, height: 9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Rectangle().fill(SiftColor.stroke).frame(height: 1)

            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowView(row)
                }
            }
            .padding(6)
        }
        .background(RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous).fill(SiftColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous)
                .strokeBorder(SiftColor.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Privacy & Security → Full Disk Access"))
    }

    private func rowView(_ row: DemoRow) -> some View {
        let highlight = row.isPureMac && (frame == .highlight)
        let succeeded = row.isPureMac && (frame == .granted || frame == .hold)

        return HStack(spacing: 12) {
            Group {
                if row.isPureMac {
                    SiftWordmark(tile: 28, showsName: false)
                } else {
                    Image(systemName: row.systemImage)
                        .font(.system(size: 13))
                        .foregroundStyle(SiftColor.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(SiftColor.control))
                }
            }

            Text(row.name)
                .font(.sift(13, weight: row.isPureMac ? 500 : 400))
                .foregroundStyle(SiftColor.textPrimary)

            Spacer()

            if succeeded {
                SiftIcon.check.image(14)
                    .foregroundStyle(SiftColor.success)
                    .transition(.scale.combined(with: .opacity))
            }

            ToggleSwitch(isOn: row.granted)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous)
                .fill(highlight ? SiftColor.accentWash : (row.isPureMac ? SiftColor.control : .clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SiftRadius.row, style: .continuous)
                .strokeBorder(highlight ? SiftColor.accent : .clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.35), value: highlight)
        .animation(.easeInOut(duration: 0.35), value: succeeded)
    }

    // MARK: - Cycle

    private func cycle() {
        guard isActive, !reduceMotion else { return }

        let schedule: [(Frame, Double)] = [
            (.idle, 0.6),
            (.highlight, 0.9),
            (.toggleOn, 0.8),
            (.granted, 0.4),
            (.hold, 1.6),
        ]

        var accumulated: Double = 0
        for (target, hold) in schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + accumulated) {
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    frame = target
                }
            }
            accumulated += hold
        }
        // Re-arm. The isActive guard at the top of cycle() is what stops the
        // chain when the view disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + accumulated + 0.4) {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                frame = .idle
            }
            cycle()
        }
    }

    private struct DemoRow {
        let name: LocalizedStringKey
        let systemImage: String
        let granted: Bool
        var isPureMac: Bool = false
    }
}

/// Tiny stand-in for the Sift switch (40×24, 18 pt thumb), drawn statically
/// so the demo controls its own animation.
private struct ToggleSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? SiftColor.accent : SiftColor.switchOff)
            Circle()
                .fill(isOn ? SiftColor.onAccent : SiftColor.textTertiary)
                .frame(width: 18, height: 18)
                .padding(3)
        }
        .frame(width: 40, height: 24)
        .animation(SiftMotion.snappy, value: isOn)
    }
}
