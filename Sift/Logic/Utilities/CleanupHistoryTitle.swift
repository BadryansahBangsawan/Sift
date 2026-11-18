import Foundation

/// The title a history row shows, resolved when the row is drawn.
///
/// Records store the title as text in the language of the day, so the history
/// used to keep the old wording after a language switch ("AI Apps", "User
/// Cache", "Emptied Trash") while every screen said "AI tools", "System junk"
/// and so on. The row now reads the stored category — or, for records written
/// before categories were stored, reads the old text back through every
/// shipped language — and names it the way the app names it today.
enum CleanupHistoryTitle {
    /// Keys a record's stored title can be: the category names the app has
    /// written, plus the titles for batches and the Trash.
    static let keys: [String] = CleaningCategory.allCases.map(\.rawValue)
        + ["Emptied Trash", "Scheduled cleanup", "Smart Scan cleanup"]

    static func text(for record: CleanupRecord) -> String {
        if let key = storedKey(of: record.title) {
            if let category = CleaningCategory(rawValue: key) {
                return localized(category.cleanupTitleKey)
            }
            return localized(key)
        }
        if let category = record.category {
            return localized(category.cleanupTitleKey)
        }
        if let title = record.title, !title.isEmpty {
            return title
        }
        return localized(record.source == .scheduled ? "Scheduled cleanup" : "Smart Scan cleanup")
    }

    // MARK: - Stored text

    /// The key whose translation is `title` in any shipped language, so a
    /// record written in German is still read as "System Junk".
    private static func storedKey(of title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        return translations[title]
    }

    /// Every translation of every key, mapped back to its key. Built once: the
    /// history list asks for it on each row.
    private static let translations: [String: String] = {
        var map: [String: String] = [:]
        for language in Bundle.main.localizations where language != "Base" {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                guard !value.isEmpty else { continue }
                // English stores the key itself; that is still a title an
                // older build wrote down.
                if map[value] == nil { map[value] = key }
            }
        }
        return map
    }()

    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }
}
