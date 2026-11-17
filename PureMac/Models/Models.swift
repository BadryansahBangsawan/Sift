import SwiftUI

// MARK: - Cleaning Category

enum CleaningCategory: String, CaseIterable, Identifiable, Codable {
    case smartScan = "Smart Scan"
    case systemJunk = "System Junk"
    case userCache = "User Cache"
    case aiApps = "AI Apps"
    case mailAttachments = "Mail Files"
    case largeFiles = "Large & Old Files"
    case installers = "Installers"
    case trash = "Trash"
    case purgeableSpace = "Purgeable Space"
    case xcodeJunk = "Xcode Junk"
    case brewCache = "Brew Cache"
    case nodeCache = "Node Cache"
    case dockerCache = "Docker Cache"
    case universalBinaries = "Universal Binaries"
    case languageFiles = "Language Files"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .smartScan: return "sparkles"
        case .systemJunk: return "gearshape.fill"
        case .userCache: return "internaldrive.fill"
        case .aiApps: return "cpu.fill"
        case .mailAttachments: return "envelope.fill"
        case .largeFiles: return "doc.fill"
        case .installers: return "archivebox.fill"
        case .trash: return "trash.fill"
        case .purgeableSpace: return "arrow.3.trianglepath"
        case .xcodeJunk: return "hammer.fill"
        case .brewCache: return "mug.fill"
        case .nodeCache: return "leaf.fill"
        case .dockerCache: return "shippingbox.fill"
        case .universalBinaries: return "cpu"
        case .languageFiles: return "globe"
        }
    }

    var description: String {
        switch self {
        case .smartScan: return "Scan everything at once"
        case .systemJunk: return "System caches, logs, and temporary files"
        case .userCache: return "Application caches and browser data"
        case .aiApps: return "Local AI app logs, caches, and optional history"
        case .mailAttachments: return "Downloaded mail attachments"
        case .largeFiles: return "Files over 100 MB or older than 1 year"
        case .installers: return "Installer disk images and packages older than two weeks"
        case .trash: return "Files in your Trash, emptied through Finder"
        case .purgeableSpace: return "Reserved by macOS - freed automatically when space is needed"
        case .xcodeJunk: return "Derived data, archives, and simulator runtimes"
        case .brewCache: return "Homebrew download cache"
        case .nodeCache: return "npm, yarn, and pnpm download caches"
        case .dockerCache: return "Docker images, containers, and build cache"
        case .universalBinaries: return "Unused CPU architecture slices in app binaries"
        case .languageFiles: return "Unused app localizations"
        }
    }

    // Categories to scan in Smart Scan mode.
    //
    // `purgeableSpace` is deliberately excluded: APFS purgeable space is
    // reserved and reclaimed by macOS itself — no third-party app can reliably
    // enumerate or free it, and the Finder's own purgeable figure is known to
    // be inaccurate. We still SHOW it in the storage breakdown for
    // transparency, but we never present it as junk PureMac can delete.
    // Honest > impressive.
    // `appModifying` is excluded too — see the note on that property. Both of
    // those categories are withdrawn as of 2.9.5 and must not be scanned,
    // surfaced, or selectable anywhere in the UI.
    //
    // `trash` is excluded as well. Its items are never unlinked by the
    // generic clean path (see CleaningEngine) and never belong to a scheduled
    // auto-clean; the Trash is emptied only by asking Finder, after the user
    // confirms. Smart Scan still measures it via `smartScanCategories`.
    static var scannable: [CleaningCategory] {
        allCases.filter {
            $0 != .smartScan && $0 != .purgeableSpace && $0 != .trash && !appModifying.contains($0)
        }
    }

    /// What Smart Scan measures: every scannable category plus the Trash, which
    /// is shown for its size but whose items start unselected and can only be
    /// removed by `AppState.emptyTrash()`.
    static var smartScanCategories: [CleaningCategory] {
        scannable + [.trash]
    }

    /// Sidebar and dashboard group for developer tool caches.
    static let developerCaches: [CleaningCategory] = [.xcodeJunk, .brewCache, .nodeCache, .dockerCache]

    /// Sidebar and dashboard group for general system and app junk.
    static let systemJunkGroup: [CleaningCategory] = [.systemJunk, .userCache, .aiApps]

    // Categories that rewrite app bundles in place (binary thinning,
    // localization stripping) instead of deleting junk.
    //
    // WITHDRAWN in 2.9.5 (issues #135, #144). Both mutate a third-party
    // bundle and then ad-hoc re-sign it, which cannot preserve the vendor's
    // Developer ID or notarization — that is cryptographic fact, not a bug
    // that can be patched. Worse, `codesign --deep` does not descend into
    // Contents/Resources, so a Mach-O there keeps the vendor signature while
    // the outer bundle becomes ad-hoc; dyld then refuses to load the pair
    // ("different Team IDs") and the app dies before showing UI. Users lost
    // 21 bundles in a single run. `codesign --verify --deep --strict` cannot
    // detect this because it checks seal consistency, not runtime Team-ID
    // compatibility.
    //
    // The cases stay in the enum for Codable compatibility with persisted
    // scan results, but `scannable` no longer includes them, so nothing
    // reaches BinaryThinner. See also the unconditional refusal in
    // BinaryThinner.stagedModify, which makes any replayed or persisted item
    // list inert.
    static var appModifying: Set<CleaningCategory> {
        [.universalBinaries, .languageFiles]
    }
}

// MARK: - Scan State

enum ScanState: Equatable {
    case idle
    case scanning(progress: Double, currentCategory: String)
    case completed
    case cleaning(progress: Double)
    case cleaned

    var isActive: Bool {
        switch self {
        case .scanning, .cleaning: return true
        default: return false
        }
    }
}

// MARK: - Cleanable Item

struct CleanableItem: Identifiable, Hashable {
    /// Path prefix for virtual items cleaned via `xcrun simctl runtime delete`
    /// rather than a filesystem unlink. The UUID after the colon is the
    /// runtime disk-image identifier from `simctl runtime list`.
    static let simctlRuntimePathPrefix = "simctl-runtime:"

    let id = UUID()
    let name: String
    let path: String
    let size: Int64
    let category: CleaningCategory
    var isSelected: Bool
    let lastModified: Date?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// True for action-only items (Docker prune, simctl runtimes) that have
    /// no real filesystem path to reveal in Finder.
    var isActionItem: Bool {
        path.isEmpty || path.hasPrefix(Self.simctlRuntimePathPrefix)
    }

    var simctlRuntimeIdentifier: String? {
        guard path.hasPrefix(Self.simctlRuntimePathPrefix) else { return nil }
        let id = String(path.dropFirst(Self.simctlRuntimePathPrefix.count))
        return id.isEmpty ? nil : id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: CleanableItem, rhs: CleanableItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Category Result

struct CategoryResult: Identifiable {
    let id = UUID()
    let category: CleaningCategory
    var items: [CleanableItem]
    var totalSize: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var itemCount: Int { items.count }
}

// MARK: - Category Group Result

/// Several categories' scan results merged for one sidebar or dashboard row.
/// Items keep their own `category`, so cleaning still routes per category.
struct CategoryGroupResult {
    let categories: [CleaningCategory]
    let items: [CleanableItem]
    let totalSize: Int64

    /// Categories without a result (not scanned yet, or emptied by a clean)
    /// contribute nothing.
    init(categories: [CleaningCategory], results: [CleaningCategory: CategoryResult]) {
        self.categories = categories
        let members = categories.compactMap { results[$0] }
        items = members.flatMap(\.items)
        totalSize = members.reduce(Int64(0)) { $0.saturatedSum($1.totalSize) }
    }

    var itemCount: Int { items.count }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

// MARK: - Schedule Settings

enum ScheduleInterval: String, CaseIterable, Identifiable, Codable {
    case hours1 = "Every Hour"
    case hours3 = "Every 3 Hours"
    case hours6 = "Every 6 Hours"
    case hours12 = "Every 12 Hours"
    case daily = "Daily"
    case weekly = "Weekly"
    case biweekly = "Every 2 Weeks"
    case monthly = "Monthly"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .hours1: return 3600
        case .hours3: return 10800
        case .hours6: return 21600
        case .hours12: return 43200
        case .daily: return 86400
        case .weekly: return 604800
        case .biweekly: return 1209600
        case .monthly: return 2592000
        }
    }
}

struct ScheduleConfig: Codable {
    var isEnabled: Bool = false
    var interval: ScheduleInterval = .daily
    /// Day a weekly schedule runs, Calendar numbering: 1 = Sunday ... 7 = Saturday.
    var weekday: Int = 1
    /// Local hour (0-23) a weekly schedule runs.
    var hour: Int = 10
    var autoClean: Bool = false
    var autoPurge: Bool = false
    var categoriesToScan: [CleaningCategory] = CleaningCategory.scannable
    var lastRunDate: Date?
    var nextRunDate: Date?
    var notifyOnCompletion: Bool = true
    var minimumCleanSize: Int64 = 100 * 1024 * 1024 // 100 MB

    var formattedLastRun: String {
        guard let date = lastRunDate else { return String(localized: "Never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var formattedNextRun: String {
        guard let date = nextRunDate else { return String(localized: "Not scheduled") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

extension ScheduleConfig {
    /// Reads configs written by older builds: missing or out-of-range
    /// `weekday`/`hour` take the defaults, and a category list naming a case
    /// this build no longer has (e.g. Trash Bins) falls back to the default
    /// scan set instead of failing the whole decode.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        interval = try container.decode(ScheduleInterval.self, forKey: .interval)
        if let day = try container.decodeIfPresent(Int.self, forKey: .weekday), (1...7).contains(day) {
            weekday = day
        }
        if let value = try container.decodeIfPresent(Int.self, forKey: .hour), (0...23).contains(value) {
            hour = value
        }
        autoClean = try container.decode(Bool.self, forKey: .autoClean)
        autoPurge = try container.decode(Bool.self, forKey: .autoPurge)
        let rawCategories = try container.decode([String].self, forKey: .categoriesToScan)
        let categories = rawCategories.compactMap(CleaningCategory.init(rawValue:))
        if categories.count == rawCategories.count {
            categoriesToScan = categories
        }
        lastRunDate = try container.decodeIfPresent(Date.self, forKey: .lastRunDate)
        nextRunDate = try container.decodeIfPresent(Date.self, forKey: .nextRunDate)
        notifyOnCompletion = try container.decode(Bool.self, forKey: .notifyOnCompletion)
        minimumCleanSize = try container.decode(Int64.self, forKey: .minimumCleanSize)
    }
}

// MARK: - Disk Info

struct DiskInfo {
    var totalSpace: Int64 = 0
    var freeSpace: Int64 = 0
    var usedSpace: Int64 = 0
    var purgeableSpace: Int64 = 0

    var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }

    var freePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(freeSpace) / Double(totalSpace)
    }

    var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalSpace, countStyle: .file)
    }

    var formattedFree: String {
        ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)
    }

    var formattedUsed: String {
        ByteCountFormatter.string(fromByteCount: usedSpace, countStyle: .file)
    }

    var formattedPurgeable: String {
        ByteCountFormatter.string(fromByteCount: purgeableSpace, countStyle: .file)
    }
}
