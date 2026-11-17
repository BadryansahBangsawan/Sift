import Foundation

/// Pure parsers behind `sift-cli doctor`, kept separate so they can be tested
/// against fixture bytes without touching the filesystem or a real disk.
enum DoctorSupport {
    /// Reads `SMARTStatus` from the plist `diskutil info -plist` prints.
    /// Returns nil when the volume reports nothing — a virtual disk or a
    /// filesystem that does not support SMART is not an error.
    static func parseSmartStatus(_ plistData: Data) -> String? {
        guard let value = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ), let dictionary = value as? [String: Any] else { return nil }
        guard let status = dictionary["SMARTStatus"] as? String else { return nil }
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Label of a launch agent plist, used to ask launchd whether the job is
    /// actually registered.
    static func launchAgentLabel(_ plistData: Data) -> String? {
        guard let value = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ), let dictionary = value as? [String: Any] else { return nil }
        guard let label = dictionary["Label"] as? String else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `launchctl list <label>` exits 0 only when launchd knows the job. A
    /// non-zero status is a real finding: the plist exists but nothing loads it.
    static func isBroken(_ status: Int32) -> Bool {
        status != 0
    }
}
