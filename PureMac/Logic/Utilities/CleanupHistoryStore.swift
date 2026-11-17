import Foundation

enum CleanupSource: String, Codable {
    case manual
    case scheduled
}

/// One completed cleanup. `id` is the timestamp: two cleanups cannot start in
/// the same instant, and deriving an identity here keeps the persisted JSON
/// free of redundant fields.
struct CleanupRecord: Codable, Identifiable, Equatable {
    let date: Date
    let freedBytes: Int64
    let source: CleanupSource

    var id: Date { date }
}

/// Append-only log of how much space each cleanup reclaimed, kept small enough
/// to read in one gulp on launch.
final class CleanupHistoryStore {
    /// Old entries are dropped rather than compacted: a year of daily cleanups
    /// is still only 200 rows, and a rollup would lose the per-run detail the
    /// dashboard card plots.
    static let maxRecords = 200

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PureMac", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// Newest first. A missing or unreadable file is not an error: before the
    /// first cleanup there is no history, and a corrupt file must not block
    /// cleaning either.
    func load() -> [CleanupRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        // Must mirror `write`: the default `.deferredToDate` strategy decodes
        // nothing from an ISO-8601 string and the whole history would read back
        // as empty on the next launch.
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([CleanupRecord].self, from: data) else { return [] }
        return records.sorted { $0.date > $1.date }
    }

    /// Appends one record and returns the trimmed list, newest first, so the
    /// caller can publish it without a second disk read.
    @discardableResult
    func record(freedBytes: Int64, source: CleanupSource, date: Date = Date()) -> [CleanupRecord] {
        var records = load()
        records.insert(CleanupRecord(date: date, freedBytes: freedBytes, source: source), at: 0)
        if records.count > Self.maxRecords {
            records.removeLast(records.count - Self.maxRecords)
        }
        write(records)
        return records
    }

    private func write(_ records: [CleanupRecord]) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
