import Foundation

/// Rules for the installer sweep. Kept free of SwiftUI so the candidate rule can
/// be exercised on its own (no app bundle, no UI).
enum InstallerScan {
    /// Only disk images and flat packages. A `.zip` or `.tar.gz` may well be a
    /// release download, but it may equally be a project archive, and guessing
    /// wrong throws away user data.
    static let extensions: Set<String> = ["dmg", "pkg"]

    /// Fresh downloads are usually still in use — someone downloaded an
    /// installer today on purpose. Two weeks of age is the point where it is
    /// a leftover rather than a pending install.
    static let minAge: TimeInterval = 14 * 24 * 60 * 60

    /// A file is an installer candidate when its extension matches and it has
    /// not been touched for `minAge`. A missing modification date disqualifies
    /// the file: without it we cannot prove the file is old.
    static func isCandidate(extension ext: String, modified: Date?, now: Date) -> Bool {
        guard extensions.contains(ext.lowercased()), let modified else { return false }
        return now.timeIntervalSince(modified) >= minAge
    }
}
