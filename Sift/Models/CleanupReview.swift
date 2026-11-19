import Foundation

enum CleanupSizeFilter: String, CaseIterable, Identifiable, Codable {
    case any = "Any size"
    case megabytes100 = "Over 100 MB"
    case gigabyte1 = "Over 1 GB"
    case gigabytes10 = "Over 10 GB"

    var id: String { rawValue }

    var minimumBytes: Int64 {
        switch self {
        case .any: return 0
        case .megabytes100: return 100_000_000
        case .gigabyte1: return 1_000_000_000
        case .gigabytes10: return 10_000_000_000
        }
    }
}

enum CleanupAgeFilter: String, CaseIterable, Identifiable, Codable {
    case any = "Any age"
    case month = "Older than 30 days"
    case sixMonths = "Older than 6 months"
    case year = "Older than a year"

    var id: String { rawValue }

    func cutoff(relativeTo now: Date) -> Date? {
        switch self {
        case .any: return nil
        case .month: return Calendar.current.date(byAdding: .day, value: -30, to: now)
        case .sixMonths: return Calendar.current.date(byAdding: .month, value: -6, to: now)
        case .year: return Calendar.current.date(byAdding: .year, value: -1, to: now)
        }
    }
}

enum CleanupSortOrder: String, CaseIterable, Identifiable, Codable {
    case largest = "Largest first"
    case smallest = "Smallest first"
    case newest = "Newest first"
    case oldest = "Oldest first"
    case name = "Name"

    var id: String { rawValue }
}

struct CleanupReviewFilter: Codable, Equatable {
    var query = ""
    var size: CleanupSizeFilter = .any
    var age: CleanupAgeFilter = .any
    var order: CleanupSortOrder = .largest

    func apply(to items: [CleanableItem], now: Date = Date()) -> [CleanableItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutoff = age.cutoff(relativeTo: now)
        return ordered(items.filter { item in
            guard item.size >= size.minimumBytes else { return false }
            if let cutoff {
                guard let modified = item.lastModified, modified < cutoff else { return false }
            }
            return search.isEmpty || item.name.localizedCaseInsensitiveContains(search)
                || item.path.localizedCaseInsensitiveContains(search)
        })
    }

    /// The rows in the order the list shows them, without the filters: the
    /// removal sheet lists what is selected in the same order the user sees it,
    /// and a row hidden by the search field is still being removed.
    func ordered(_ items: [CleanableItem]) -> [CleanableItem] {
        items.sorted(by: compare)
    }

    private func compare(_ left: CleanableItem, _ right: CleanableItem) -> Bool {
        switch order {
        case .largest where left.size != right.size: return left.size > right.size
        case .smallest where left.size != right.size: return left.size < right.size
        case .newest where left.lastModified != right.lastModified:
            return (left.lastModified ?? .distantPast) > (right.lastModified ?? .distantPast)
        case .oldest where left.lastModified != right.lastModified:
            return (left.lastModified ?? .distantFuture) < (right.lastModified ?? .distantFuture)
        default:
            let comparison = left.name.localizedStandardCompare(right.name)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return left.path < right.path
        }
    }
}

/// A named set of filters, either shipped with the app or saved by the user for
/// one category.
struct CleanupFilterPreset: Codable, Identifiable, Equatable {
    let name: String
    let filter: CleanupReviewFilter

    var id: String { name }

    /// Filter combinations people actually reach for: the three questions the
    /// size and age filters exist to answer, without making them assemble it.
    static let builtIns: [CleanupFilterPreset] = [
        CleanupFilterPreset(
            name: String(localized: "Bulky (over 1 GB)"),
            filter: CleanupReviewFilter(query: "", size: .gigabyte1, age: .any, order: .largest)
        ),
        CleanupFilterPreset(
            name: String(localized: "Old and large"),
            filter: CleanupReviewFilter(query: "", size: .megabytes100, age: .year, order: .largest)
        ),
        CleanupFilterPreset(
            name: String(localized: "Over 10 GB"),
            filter: CleanupReviewFilter(query: "", size: .gigabytes10, age: .any, order: .largest)
        ),
    ]

    private static func key(forCategory rawValue: String) -> String {
        "settings.filters.preset.\(rawValue)"
    }

    static func savedPreset(forCategory rawValue: String) -> CleanupFilterPreset? {
        guard let data = UserDefaults.standard.data(forKey: key(forCategory: rawValue)) else { return nil }
        return try? JSONDecoder().decode(CleanupFilterPreset.self, from: data)
    }

    static func savePreset(_ preset: CleanupFilterPreset, forCategory rawValue: String) {
        guard let data = try? JSONEncoder().encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: key(forCategory: rawValue))
    }

    static func clearSavedPreset(forCategory rawValue: String) {
        UserDefaults.standard.removeObject(forKey: key(forCategory: rawValue))
    }
}
