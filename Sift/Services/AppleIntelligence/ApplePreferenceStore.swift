import Foundation

/// A preference value, with the type it was written as. Booleans and 0/1 match
/// because `defaults write -int 1` and `-bool true` both happen in the wild.
enum ApplePreferenceValue: Equatable, Codable, CustomStringConvertible {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    init?(_ any: Any?) {
        guard let any else { return nil }
        if let string = any as? String {
            self = .string(string)
        } else if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        } else {
            return nil
        }
    }

    var object: CFPropertyList {
        switch self {
        case .bool(let value): return value as CFBoolean
        case .int(let value): return value as CFNumber
        case .double(let value): return value as CFNumber
        case .string(let value): return value as CFString
        }
    }

    var commandType: String {
        switch self {
        case .bool: return "-bool"
        case .int: return "-int"
        case .double: return "-float"
        case .string: return "-string"
        }
    }

    func matches(_ stored: Any?) -> Bool {
        guard let other = ApplePreferenceValue(stored) else { return false }
        switch (self, other) {
        case (.bool(let mine), .int(let theirs)), (.int(let theirs), .bool(let mine)):
            return (theirs != 0) == mine
        case (.double(let mine), .int(let theirs)), (.int(let theirs), .double(let mine)):
            return mine == Double(theirs)
        default:
            return self == other
        }
    }

    func matches(_ other: ApplePreferenceValue?) -> Bool {
        guard let other else { return false }
        switch (self, other) {
        case (.bool(let mine), .int(let theirs)), (.int(let theirs), .bool(let mine)):
            return (theirs != 0) == mine
        case (.double(let mine), .int(let theirs)), (.int(let theirs), .double(let mine)):
            return mine == Double(theirs)
        default:
            return self == other
        }
    }

    var description: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .string(let value): return "\"\(value)\""
        }
    }
}

/// Reads and writes preferences through cfprefsd, the way `defaults` does.
protocol ApplePreferenceStoring {
    /// The value apps see; a forced value from a profile wins over the user's.
    func read(domain: String, key: String) -> ApplePreferenceValue?
    /// The user's own value, ignoring a forced value.
    func userValue(domain: String, key: String) -> ApplePreferenceValue?
    func isForced(domain: String, key: String) -> Bool
    /// Writes the user's value; nil removes it so the macOS default applies.
    func write(_ value: ApplePreferenceValue?, domain: String, key: String)
}

struct CFPreferencesStore: ApplePreferenceStoring {
    static let anyApplication = "kCFPreferencesAnyApplication"
    private static let globalDomains: Set<String> = [
        "NSGlobalDomain", ".GlobalPreferences", anyApplication,
    ]

    private func application(_ domain: String) -> CFString {
        Self.globalDomains.contains(domain) ? kCFPreferencesAnyApplication : domain as CFString
    }

    func read(domain: String, key: String) -> ApplePreferenceValue? {
        let app = application(domain)
        CFPreferencesAppSynchronize(app)
        return ApplePreferenceValue(CFPreferencesCopyAppValue(key as CFString, app))
    }

    func userValue(domain: String, key: String) -> ApplePreferenceValue? {
        let app = application(domain)
        CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return ApplePreferenceValue(
            CFPreferencesCopyValue(
                key as CFString, app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost))
    }

    func isForced(domain: String, key: String) -> Bool {
        let app = application(domain)
        CFPreferencesAppSynchronize(app)
        return CFPreferencesAppValueIsForced(key as CFString, app)
    }

    func write(_ value: ApplePreferenceValue?, domain: String, key: String) {
        let app = application(domain)
        CFPreferencesSetValue(
            key as CFString, value?.object, app, kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost)
        CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
