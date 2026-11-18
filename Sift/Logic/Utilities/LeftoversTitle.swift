import Foundation

/// The Leftovers page's own name, with a count only once a scan has finished.
///
/// A fresh page used to say "Orphaned Files (0)": a second name for the screen
/// and a number that meant "nothing found" when it meant "nothing looked at".
enum LeftoversTitle {
    static func text(count: Int, scanned: Bool) -> String {
        guard scanned else { return String(localized: "Leftovers") }
        return String(format: String(localized: "Leftovers (%lld)"), Int64(count))
    }
}
