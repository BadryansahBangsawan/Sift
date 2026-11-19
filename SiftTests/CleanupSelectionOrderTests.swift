import XCTest

@testable import Sift

/// The removal sheet lists what is about to go. It used to print the rows in
/// raw scan order, so a list sorted by name produced a sheet sorted at random
/// (131 KB, 66 KB, 328 KB, …). The sheet now follows the list's own sort.
final class CleanupSelectionOrderTests: XCTestCase {
    private func items() -> [CleanableItem] {
        [
            item("Bravo", size: 2_000, date: Date(timeIntervalSince1970: 20)),
            item("Alpha", size: 3_000, date: Date(timeIntervalSince1970: 10)),
            item("Charlie", size: 1_000, date: Date(timeIntervalSince1970: 30)),
        ]
    }

    func testTheOrderFollowsTheListsSort() {
        XCTAssertEqual(
            CleanupReviewFilter(order: .name).ordered(items()).map(\.name),
            ["Alpha", "Bravo", "Charlie"])
        XCTAssertEqual(
            CleanupReviewFilter(order: .largest).ordered(items()).map(\.name),
            ["Alpha", "Bravo", "Charlie"])
        XCTAssertEqual(
            CleanupReviewFilter(order: .smallest).ordered(items()).map(\.name),
            ["Charlie", "Bravo", "Alpha"])
        XCTAssertEqual(
            CleanupReviewFilter(order: .newest).ordered(items()).map(\.name),
            ["Charlie", "Bravo", "Alpha"])
        XCTAssertEqual(
            CleanupReviewFilter(order: .oldest).ordered(items()).map(\.name),
            ["Alpha", "Bravo", "Charlie"])
    }

    /// The sheet orders the selection, it does not filter it: rows hidden by
    /// the search, size or age filter are still being removed and still show.
    func testTheOrderKeepsRowsTheFilterHides() {
        let filter = CleanupReviewFilter(query: "alpha", size: .any, age: .any, order: .largest)
        XCTAssertEqual(filter.apply(to: items()).map(\.name), ["Alpha"])
        XCTAssertEqual(filter.ordered(items()).count, 3, "Ordering must not drop rows")
        XCTAssertEqual(filter.ordered(items()).map(\.name), ["Alpha", "Bravo", "Charlie"])
    }

    private func item(_ name: String, size: Int64, date: Date?) -> CleanableItem {
        CleanableItem(
            name: name, path: "/fixture/\(name)", size: size, category: .systemJunk,
            isSelected: true, lastModified: date)
    }

    // MARK: - Edges

    /// Equal sizes fall back to the name, and a row with no date sorts last
    /// under both date orders — the list's own tie rules, since the sheet must
    /// not reshuffle them.
    func testTiesFollowTheListsOwnRules() {
        let sameSize = [item("Charlie", size: 10, date: nil),
                        item("Alpha", size: 10, date: nil),
                        item("Bravo", size: 10, date: nil)]
        XCTAssertEqual(
            CleanupReviewFilter(order: .largest).ordered(sameSize).map(\.name),
            ["Alpha", "Bravo", "Charlie"])

        let dated = [item("Zed", size: 10, date: nil),
                     item("Amy", size: 10, date: Date(timeIntervalSince1970: 5))]
        XCTAssertEqual(CleanupReviewFilter(order: .newest).ordered(dated).map(\.name), ["Amy", "Zed"])
        XCTAssertEqual(CleanupReviewFilter(order: .oldest).ordered(dated).map(\.name), ["Amy", "Zed"],
                       "A row with no date is not the oldest one")
    }

    /// Ordering is a view of the rows, not a rewrite of them: same rows, same
    /// selection, nothing dropped or duplicated.
    func testOrderingKeepsEveryRowExactlyOnce() {
        let rows = items()
        let ordered = CleanupReviewFilter(order: .smallest).ordered(rows)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(rows.map(\.id)))
        XCTAssertEqual(ordered.count, rows.count)
        XCTAssertTrue(ordered.allSatisfy(\.isSelected))
    }
}
