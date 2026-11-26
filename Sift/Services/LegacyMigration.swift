import Foundation

/// One-time import of a PureMac install's settings and data into Sift.
///
/// The bundle identifier changed with the rename, so macOS gives Sift a fresh
/// defaults domain. On first launch this copies every key from the old domain
/// that the new one doesn't already have, and copies the old Application
/// Support folder when Sift has none yet. The old data is never modified, so
/// PureMac keeps working if it is still installed.
enum LegacyMigration {
    static let legacyBundleIdentifier = "com.puremac.app"
    static let doneKey = "Sift.LegacyMigrationDone"

    /// Production entry point, called once at launch.
    static func runIfNeeded() {
        guard let old = UserDefaults(suiteName: legacyBundleIdentifier),
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        run(
            oldDefaults: old,
            newDefaults: .standard,
            oldSupport: support.appendingPathComponent("PureMac", isDirectory: true),
            newSupport: support.appendingPathComponent("Sift", isDirectory: true)
        )
    }

    static func run(
        oldDefaults: UserDefaults,
        newDefaults: UserDefaults,
        oldSupport: URL,
        newSupport: URL,
        fileManager: FileManager = .default
    ) {
        guard !newDefaults.bool(forKey: doneKey) else { return }

        let existing = newDefaults.dictionaryRepresentation()
        for (key, value) in oldDefaults.dictionaryRepresentation() where existing[key] == nil {
            newDefaults.set(value, forKey: key)
        }

        if fileManager.fileExists(atPath: oldSupport.path), !fileManager.fileExists(atPath: newSupport.path) {
            do {
                try fileManager.createDirectory(at: newSupport.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: oldSupport, to: newSupport)
            } catch {
                Logger.shared.log("Legacy data copy failed: \(error.localizedDescription)", level: .warning)
                // Leave the done key unset: the next launch retries instead of
                // stranding the old PureMac data forever.
                return
            }
        }

        newDefaults.set(true, forKey: doneKey)
    }
}
