import Darwin
import Foundation
import IOKit

/// Static facts about this Mac: its model and its macOS version.
///
/// The live values read the kernel and the IORegistry each time they are
/// accessed; they are cheap, but callers that render often should keep the
/// result. The parsing and mapping helpers are pure so they can be tested.
enum SystemInfo {
    /// Model identifier such as "Mac16,12" or "MacBookPro18,3" (`hw.model`).
    static var modelIdentifier: String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer)
        return value.isEmpty ? nil : value
    }

    /// Full marketing name with detail, such as "MacBook Air (13-inch, M4, 2025)".
    /// Apple silicon Macs publish it in the device tree; Intel Macs do not, so
    /// this is nil there.
    static var productName: String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Data
        else { return nil }
        return productName(fromRegistryData: value)
    }

    /// Short marketing name such as "MacBook Pro", "Mac mini" or "Mac Studio".
    static var modelName: String {
        modelName(productName: productName, modelIdentifier: modelIdentifier)
    }

    /// The running OS, such as "macOS 26.2" (patch shown only when non-zero).
    static var macOSVersion: String {
        macOSVersionString(ProcessInfo.processInfo.operatingSystemVersion)
    }

    /// Prefers the product name without its "(13-inch, M4, 2025)" detail, then
    /// the family the model identifier names, then plain "Mac". Apple silicon
    /// identifiers are all "MacNN,N", so without a product name they map to "Mac".
    static func modelName(productName: String?, modelIdentifier: String?) -> String {
        if let productName {
            let base = productName
                .split(separator: "(", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            if !base.isEmpty { return base }
        }
        guard let modelIdentifier else { return "Mac" }
        // Longest prefixes first: "MacBookPro" must not match "MacBook".
        let families: [(prefix: String, name: String)] = [
            ("MacBookPro", "MacBook Pro"),
            ("MacBookAir", "MacBook Air"),
            ("MacBook", "MacBook"),
            ("Macmini", "Mac mini"),
            ("MacPro", "Mac Pro"),
            ("iMacPro", "iMac Pro"),
            ("iMac", "iMac"),
        ]
        return families.first { modelIdentifier.hasPrefix($0.prefix) }?.name ?? "Mac"
    }

    /// Decodes the device tree's NUL-terminated C string.
    static func productName(fromRegistryData data: Data) -> String? {
        let bytes = data.prefix { $0 != 0 }
        let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func macOSVersionString(_ version: OperatingSystemVersion) -> String {
        var string = "macOS \(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 {
            string += ".\(version.patchVersion)"
        }
        return string
    }
}
