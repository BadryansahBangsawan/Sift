import Foundation

/// Dry run of an app uninstall: what would be removed, grouped and sized,
/// without touching the file system beyond reading sizes.
///
/// Build it from the same selection the remove button acts on:
///
///     let plan = UninstallPlan(files: appState.selectedFiles)
///     plan.entries      // ordered by LeftoverGroup.allCases, then path
///     plan.totalSize    // bytes
struct UninstallPlan {
    struct Entry: Identifiable, Equatable {
        let url: URL
        let group: LeftoverGroup
        /// Allocated bytes on disk; 0 when the item can't be read.
        let size: Int64

        var id: URL { url }
    }

    let entries: [Entry]

    var totalSize: Int64 { entries.reduce(0) { $0 + $1.size } }

    /// `sizeOf` is injectable for tests; it defaults to the recursive on-disk size.
    init(files: some Collection<URL>, sizeOf: (URL) -> Int64? = FileSizeCalculator.size(of:)) {
        let order = Dictionary(uniqueKeysWithValues: LeftoverGroup.allCases.enumerated().map { ($1, $0) })
        entries = files
            .map { Entry(url: $0, group: LeftoverGroup.categorize($0), size: sizeOf($0) ?? 0) }
            .sorted {
                let lhs = order[$0.group, default: 0], rhs = order[$1.group, default: 0]
                return lhs != rhs ? lhs < rhs : $0.url.path < $1.url.path
            }
    }
}
