import Foundation

/// Append-only, local audit trail of every path Sift moves to the Trash or
/// deletes. One JSON object per line at `~/Library/Logs/Sift/cleanup.log`.
///
/// The log contains paths only, never file contents, and is never uploaded.
/// Logging must never fail a cleanup: a write error is reported through the
/// regular `Logger` and swallowed.
final class CleanupLog: @unchecked Sendable {
    enum Action: String {
        case trashed
        case removed
        case removedWithAdmin
        case skipped
        case failed
    }

    struct Record: Codable, Equatable {
        let time: String
        let version: String
        let build: String
        let source: String
        let category: String?
        let action: String
        let path: String
        let bytes: Int64?
        let reason: String?
    }

    static let shared = CleanupLog()

    static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Sift/cleanup.log", isDirectory: false)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    let fileURL: URL
    private let clock: () -> Date
    private let fileManager: FileManager
    private let version: String
    private let build: String
    private let maxBytes: Int
    private let lock = NSLock()
    private let formatter = ISO8601DateFormatter()

    init(
        fileURL: URL = CleanupLog.defaultFileURL,
        clock: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default,
        version: String = CleanupLog.appVersion,
        build: String = CleanupLog.appBuild,
        maxBytes: Int = 5 * 1_024 * 1_024
    ) {
        self.fileURL = fileURL
        self.clock = clock
        self.fileManager = fileManager
        self.version = version
        self.build = build
        self.maxBytes = max(1, maxBytes)
    }

    func record(
        source: String,
        category: String?,
        action: Action,
        path: String,
        bytes: Int64? = nil,
        reason: String? = nil
    ) {
        let record = Record(
            time: formatter.string(from: clock()),
            version: version,
            build: build,
            source: source,
            category: category,
            action: action.rawValue,
            path: path,
            bytes: bytes,
            reason: reason
        )
        write(record)
    }

    private func write(_ record: Record) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            var line = try encoder.encode(record)
            line.append(0x0A)

            try ensureDirectory()
            let currentSize = (try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            if currentSize > 0, currentSize + line.count > maxBytes {
                try rotate()
            }
            if !fileManager.fileExists(atPath: fileURL.path) {
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            Logger.shared.log(
                "Could not write the cleanup log at \(fileURL.path): \(error.localizedDescription)",
                level: .warning
            )
        }
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func rotate() throws {
        let archived = fileURL.appendingPathExtension("1")
        if fileManager.fileExists(atPath: archived.path) {
            try fileManager.removeItem(at: archived)
        }
        try fileManager.moveItem(at: fileURL, to: archived)
    }
}