import AppKit
import SwiftUI

/// Draggable Sift.app affordance. The user grabs the icon out of our sheet
/// and drops it into the Full Disk Access list inside System Settings, which
/// auto-adds the bundle without making them hunt for it in Finder.
///
/// macOS's Privacy & Security panes accept file-URL drops in their service
/// lists. We expose the running app's bundle URL via `NSItemProvider` so the
/// drop registers as a legitimate filesystem drag — identical to dragging
/// from Finder, just sourced from inside the app.
struct AppBundleDragHandle: View {
    @State private var hovering = false

    private var bundleURL: URL {
        Bundle.main.bundleURL
    }

    var body: some View {
        VStack(spacing: 10) {
            appIcon
                .frame(width: 52, height: 52)
                .scaleEffect(hovering ? 1.04 : 1.0)
                .frame(width: 84, height: 84)
                .background(
                    RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous)
                        .fill(hovering ? SiftColor.accentWash : SiftColor.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SiftRadius.panel, style: .continuous)
                        .strokeBorder(
                            hovering ? SiftColor.accent : SiftColor.checkboxStroke,
                            style: StrokeStyle(lineWidth: hovering ? 1.5 : 1, dash: hovering ? [] : [4, 4])
                        )
                )
                .animation(SiftMotion.quick, value: hovering)

            VStack(spacing: 2) {
                // The real bundle name, so it matches what Finder and System Settings show.
                Text(verbatim: bundleURL.lastPathComponent)
                    .font(.siftMono(11))
                    .foregroundStyle(SiftColor.textPrimary)
                Text("Drag to the Settings list")
                    .font(.sift(11))
                    .foregroundStyle(SiftColor.textTertiary)
            }
        }
        .padding(12)
        .onHover { hovering = $0 }
        .help("Drag this icon into the Full Disk Access list in System Settings.")
        // NSItemProvider(object: NSURL) is exactly what Finder emits when
        // you drag an .app — it exposes both the file representation and
        // the URL string under public.file-url, which is the shape System
        // Settings' Privacy panes are built to receive. `contentsOf:` works
        // too but registers as a generic file copy operation; Settings'
        // FDA list reads the URL representation directly.
        .onDrag {
            let provider = NSItemProvider(object: bundleURL as NSURL)
            provider.suggestedName = bundleURL.lastPathComponent
            return provider
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let nsImage = NSWorkspace.shared.icon(forFile: bundleURL.path) as NSImage? {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
        } else {
            SiftWordmark(tile: 44, showsName: false)
        }
    }
}
