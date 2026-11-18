import SwiftUI
import AppKit

/// Zero-size helper that captures SwiftUI's `openWindow` action into
/// `WindowOpener.shared` when the main window appears, so the AppKit menu-bar
/// popover can reopen the window after it's been closed.
struct WindowOpenerCapture: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { WindowOpener.shared.open = { id in openWindow(id: id) } }
            .background(MainWindowReference())
    }
}

private struct MainWindowReference: NSViewRepresentable {
    func makeNSView(context: Context) -> ReferenceView { ReferenceView() }
    func updateNSView(_ nsView: ReferenceView, context: Context) {}

    final class ReferenceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { WindowOpener.shared.mainWindow = window }
        }
    }
}

/// Drop-down panel hosted in the menu-bar `NSPopover` (via `NSHostingController`)
/// with live CPU / memory / disk meters and quick actions. Kept self-contained
/// so the menu bar surface stays decoupled from the main window's `AppState`.
struct MenuBarMonitorView: View {
    @ObservedObject private var monitor = SystemMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                SiftWordmark(tile: 20, showsName: false)
                Text("System Monitor")
                    .siftStyle(.cardTitle)
            }

            VStack(spacing: 12) {
                MeterRow(title: "CPU", fill: SiftColor.accent,
                         fraction: monitor.cpuUsage,
                         detail: "\(Int((monitor.cpuUsage * 100).rounded()))%")
                MeterRow(title: "Memory", fill: SiftColor.accentDim,
                         fraction: monitor.memoryFraction,
                         detail: Self.memoryDetail(used: monitor.memoryUsed, total: monitor.memoryTotal))
                MeterRow(title: "Disk", fill: SiftColor.textTertiary,
                         fraction: monitor.diskFraction,
                         detail: Self.diskDetail(used: monitor.diskUsed, total: monitor.diskTotal))
            }

            Rectangle()
                .fill(SiftColor.stroke)
                .frame(height: 1)

            HStack(spacing: 8) {
                Button {
                    openMainWindow()
                } label: {
                    Text("Open Sift")
                }
                .buttonStyle(.sift(.primary, compact: true))

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit Sift")
                }
                .buttonStyle(.sift(.quiet, compact: true))
            }
        }
        .padding(16)
        .frame(width: 260)
        // The owning MenuBarController keeps telemetry alive for the status
        // item and popover together, and releases it explicitly on teardown.
    }

    /// Disk usage in the same decimal units the dashboard shows, so the popover
    /// and the Overview quote one total for the same disk.
    static func diskDetail(used: Int64, total: Int64) -> String {
        "\(SiftFormat.bytes(used)) / \(SiftFormat.bytes(total))"
    }

    /// RAM is a binary quantity: a 16 GB Mac holds 17,179,869,184 bytes, which
    /// macOS and the Performance screen show as 16 GB.
    static func memoryDetail(used: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(0, used))
            + " / "
            + formatter.string(fromByteCount: max(0, total))
    }

    /// Bring the app forward and surface the main window. The app stays alive
    /// after its window closes only while the monitor is enabled (see
    /// `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`), so this
    /// reopens a fresh window when none is left, otherwise just focuses it.
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Exclude the menu-bar popover's own panel; a real content window is
        // titled and can become main.
        if let existing = NSApp.windows.first(where: {
            $0.canBecomeMain && $0.styleMask.contains(.titled)
        }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            // No content window left — reopen via the captured openWindow action
            // (the popover has no working openWindow environment of its own).
            WindowOpener.shared.open?("main")
        }
    }
}

/// One labeled meter: title on the left, a mono value on the right and a
/// thin Sift meter underneath.
private struct MeterRow: View {
    let title: LocalizedStringKey
    let fill: Color
    let fraction: Double
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.sift(11.5))
                    .foregroundStyle(SiftColor.textTertiary)
                Spacer()
                Text(detail)
                    .font(.siftMono(11))
                    .foregroundStyle(SiftColor.textPrimary)
            }
            SiftMeterBar(fraction: fraction, fill: fill)
        }
        .accessibilityElement(children: .combine)
    }
}
