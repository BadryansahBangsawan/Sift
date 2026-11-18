import XCTest
@testable import Sift

/// `visibleItems` feeds the list, both toolbar counters and the selection bar,
/// so a single body pass during a clean ran the filter and the sort over every
/// row four times. With thousands of rows that is the multi-second freeze.
final class VisibleItemsCacheTests: XCTestCase {
    func testUnchangedInputsReuseTheFilteredRows() {
        let cache = VisibleItemsCache()
        let items = makeItems(40)

        let first = cache.items(for: items, filter: CleanupReviewFilter())
        for _ in 0..<20 { _ = cache.items(for: items, filter: CleanupReviewFilter()) }
        let last = cache.items(for: items, filter: CleanupReviewFilter())

        XCTAssertEqual(cache.recomputations, 1, "Expected one filter pass for repeated identical reads")
        XCTAssertEqual(first.map(\.id), last.map(\.id))
    }

    func testFilterChangeRecomputes() {
        let cache = VisibleItemsCache()
        let items = makeItems(40)

        _ = cache.items(for: items, filter: CleanupReviewFilter())
        var filter = CleanupReviewFilter()
        filter.query = "1"
        let filtered = cache.items(for: items, filter: filter)

        XCTAssertEqual(cache.recomputations, 2)
        XCTAssertEqual(filtered.map(\.id), filter.apply(to: items).map(\.id))
    }

    func testItemListChangeRecomputes() {
        let cache = VisibleItemsCache()
        var items = makeItems(10)

        _ = cache.items(for: items, filter: CleanupReviewFilter())
        items.append(contentsOf: makeItems(5))
        let updated = cache.items(for: items, filter: CleanupReviewFilter())

        XCTAssertEqual(cache.recomputations, 2)
        XCTAssertEqual(updated.count, 15)
    }

    /// A selection tick does not change which rows are visible, and the rows
    /// compare by identity, so ticking a box must not pay for a new sort.
    func testSelectionTicksDoNotRecompute() {
        let cache = VisibleItemsCache()
        var items = makeItems(12)

        let before = cache.items(for: items, filter: CleanupReviewFilter())
        for index in items.indices { items[index].isSelected = true }
        let after = cache.items(for: items, filter: CleanupReviewFilter())

        XCTAssertEqual(cache.recomputations, 1)
        XCTAssertEqual(before.map(\.id), after.map(\.id))
    }

    /// Changing the sort order is a filter change, so the rows are rebuilt in
    /// the new order instead of serving the cached order.
    func testSortChangeRecomputesInTheNewOrder() {
        let cache = VisibleItemsCache()
        let items = makeItems(20)

        let largestFirst = cache.items(for: items, filter: CleanupReviewFilter())
        var smallestFirst = CleanupReviewFilter()
        smallestFirst.order = .smallest
        let smallest = cache.items(for: items, filter: smallestFirst)

        XCTAssertEqual(cache.recomputations, 2)
        XCTAssertNotEqual(largestFirst.map(\.id), smallest.map(\.id))
        XCTAssertEqual(largestFirst.first?.size, items.map(\.size).max())
        XCTAssertEqual(smallest.first?.size, items.map(\.size).min())
    }

    func testEmptyItemsAreCachedToo() {
        let cache = VisibleItemsCache()

        XCTAssertTrue(cache.items(for: [], filter: CleanupReviewFilter()).isEmpty)
        XCTAssertTrue(cache.items(for: [], filter: CleanupReviewFilter()).isEmpty)
        XCTAssertEqual(cache.recomputations, 1)
    }

    // MARK: - Helpers

    private func makeItems(_ count: Int) -> [CleanableItem] {
        (0..<count).map { index in
            CleanableItem(
                name: "row\(index)",
                path: "/fixture/row\(index)",
                size: Int64(1_024 * (count - index)),
                category: .userCache,
                isSelected: false,
                lastModified: nil
            )
        }
    }
}
