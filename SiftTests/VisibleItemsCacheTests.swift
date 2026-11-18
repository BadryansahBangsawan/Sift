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
