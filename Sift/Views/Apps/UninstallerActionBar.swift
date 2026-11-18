import AppKit
import SwiftUI

/// The Uninstaller's footer: what is selected, and what can be done with it.
///
/// Split out of `AppFilesView` so a render test can build it at the minimum
/// window width and check that the selection summary is not squeezed out
/// between the buttons.
struct UninstallerActionBar: View {
    let summary: String
    let canDryRun: Bool
    let canReview: Bool
    /// The running app's name while it is open: reviewing is refused and the
    /// button explains why.
    let runningAppName: String?
    let showInFinder: () -> Void
    let dryRun: () -> Void
    let review: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // The summary has a line of its own: between the two buttons it
            // was squeezed to a few points at the minimum window width.
            Text(verbatim: summary)
                .font(.siftMono(12))
                .foregroundStyle(SiftColor.textTertiary)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .accessibilityIdentifier("uninstaller.selectionSummary")

            HStack(spacing: 8) {
                Button(action: showInFinder) {
                    barButtonLabel("Show in Finder", icon: .folderOpen)
                }
                .buttonStyle(.siftSecondary)

                Button(action: dryRun) {
                    barButtonLabel("Dry run", icon: .flaskConical)
                }
                .buttonStyle(.siftSecondary)
                .disabled(!canDryRun)
                .help("List what would be removed without removing anything")
                .accessibilityIdentifier("uninstaller.dryRun")

                Spacer(minLength: 8)

                Button(action: review) {
                    HStack(spacing: 8) {
                        SiftIcon.trash2.image(15)
                        Text("Review removal").font(.sift(13))
                        SiftKeyHint("⏎", onAccent: true)
                    }
                    .fixedSize()
                }
                .buttonStyle(.siftPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(!canReview)
                .help(runningAppName.map { Text("Quit \($0) before removing.") }
                    ?? Text("Review the selected files before they move to the Trash"))
                .accessibilityIdentifier("uninstaller.reviewRemoval")
            }
        }
    }

    /// "25 items, 1.12 GB" — pluralised by the stringsdict entry, which carries
    /// the number of files and the size they take.
    static func summary(count: Int, size: Int64) -> String {
        String(format: String(localized: "%lld items, %@"), count, SiftFormat.bytes(size))
    }

    private func barButtonLabel(_ title: LocalizedStringKey, icon: SiftIcon) -> some View {
        HStack(spacing: 8) {
            icon.image(15).foregroundStyle(SiftColor.textSecondary)
            Text(title)
        }
        .fixedSize()
    }
}
