import XCTest
@testable import OneButton

final class DesktopSortTests: XCTestCase {
    func testNameUsesNaturalOrderInBothDirections() {
        let items = [item("문서 10.txt"), item("문서 2.txt"), item("문서 1.txt")]
        XCTAssertEqual(names(DesktopSort.name.sorted(items, direction: .ascending)), ["문서 1.txt", "문서 2.txt", "문서 10.txt"])
        XCTAssertEqual(names(DesktopSort.name.sorted(items, direction: .descending)), ["문서 10.txt", "문서 2.txt", "문서 1.txt"])
    }

    func testEveryMetadataCriterionUsesItsValueAndKeepsMissingValuesLast() {
        let low = populatedItem("문서 10.txt", rank: 2)
        let high = populatedItem("문서 2.txt", rank: 10)
        let missing = item("문서 0.txt")
        for criterion in DesktopSort.allCases where criterion != .name {
            let items = [missing, high, low]
            XCTAssertEqual(criterion.sorted(items, direction: .ascending).map(\.id), [low.id, high.id, missing.id], criterion.rawValue)
            XCTAssertEqual(criterion.sorted(items, direction: .descending).map(\.id), [high.id, low.id, missing.id], criterion.rawValue)
        }
    }

    func testEachDateCriterionUsesItsOwnTimestamp() {
        var first = item("a.txt")
        var second = item("b.txt")
        var third = item("c.txt")
        let early = Date(timeIntervalSince1970: 100)
        let middle = Date(timeIntervalSince1970: 200)
        let late = Date(timeIntervalSince1970: 300)
        first.lastUsedDate = late
        second.lastUsedDate = early
        third.lastUsedDate = middle
        first.addedDate = early
        second.addedDate = middle
        third.addedDate = late
        first.modifiedDate = middle
        second.modifiedDate = late
        third.modifiedDate = early
        first.createdDate = late
        second.createdDate = middle
        third.createdDate = early
        let items = [first, second, third]

        XCTAssertEqual(DesktopSort.lastUsed.sorted(items, direction: .ascending).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(DesktopSort.added.sorted(items, direction: .ascending).map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(DesktopSort.modified.sorted(items, direction: .ascending).map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(DesktopSort.created.sorted(items, direction: .ascending).map(\.id), [third.id, second.id, first.id])
    }

    func testEmptyMetadataIsMissingAndMissingTiesUseNaturalNameOrder() {
        var empty = item("문서 2.txt")
        empty.kind = ""
        empty.applicationName = ""
        empty.tags = [""]
        let missing = item("문서 10.txt")
        let known = populatedItem("문서 99.txt", rank: 1)
        for criterion in [DesktopSort.kind, .application, .tags] {
            for direction in DesktopSortDirection.allCases {
                XCTAssertEqual(criterion.sorted([missing, empty, known], direction: direction).map(\.id), [known.id, empty.id, missing.id])
            }
        }
    }

    func testTagNamesAreComparedAsNaturalSortedListsWithoutMutatingSource() {
        var prefix = item("prefix.txt")
        prefix.tags = ["tag 2"]
        var first = item("문서 2.txt")
        first.tags = ["tag 10", "tag 2"]
        var same = item("문서 10.txt")
        same.tags = ["tag 2", "tag 10"]
        var later = item("later.txt")
        later.tags = ["tag 10"]
        let items = [later, same, prefix, first]
        let original = items

        XCTAssertEqual(DesktopSort.tags.sorted(items, direction: .ascending).map(\.id), [prefix.id, first.id, same.id, later.id])
        XCTAssertEqual(DesktopSort.tags.sorted(items, direction: .descending).map(\.id), [later.id, first.id, same.id, prefix.id])
        XCTAssertEqual(items, original)
    }

    func testEqualValuesUseNaturalNamesThenExactPathsInBothDirections() {
        let first = populatedItem("문서 2.txt", rank: 1, path: "/test/a")
        let sameName = populatedItem("문서 2.txt", rank: 1, path: "/test/z")
        let later = populatedItem("문서 10.txt", rank: 1)
        for criterion in DesktopSort.allCases where criterion != .name {
            for direction in DesktopSortDirection.allCases {
                XCTAssertEqual(criterion.sorted([later, sameName, first], direction: direction).map(\.id), [first.id, sameName.id, later.id], criterion.rawValue)
            }
        }
        for direction in DesktopSortDirection.allCases {
            XCTAssertEqual(DesktopSort.name.sorted([sameName, first], direction: direction).map(\.id), [first.id, sameName.id])
        }
    }

    func testOrderingIsIndependentOfInputOrderAndIdempotent() {
        let items = [populatedItem("문서 2.txt", rank: 2), populatedItem("문서 10.txt", rank: 2), populatedItem("문서 1.txt", rank: 10), item("문서 0.txt")]
        for criterion in DesktopSort.allCases {
            for direction in DesktopSortDirection.allCases {
                let expected = criterion.sorted(items, direction: direction)
                for permutation in permutations(items) {
                    XCTAssertEqual(criterion.sorted(permutation, direction: direction), expected, "\(criterion) \(direction)")
                }
                XCTAssertEqual(criterion.sorted(expected, direction: direction), expected)
            }
        }
    }

    private func item(_ name: String, path: String? = nil) -> DesktopItem {
        DesktopItem(url: URL(fileURLWithPath: path ?? "/test/\(name)"), name: name, isDirectory: false)
    }

    private func populatedItem(_ name: String, rank: Int, path: String? = nil) -> DesktopItem {
        var result = item(name, path: path)
        result.size = rank
        result.kind = "종류 \(rank)"
        result.lastUsedDate = Date(timeIntervalSince1970: Double(rank))
        result.addedDate = result.lastUsedDate
        result.modifiedDate = result.lastUsedDate
        result.createdDate = result.lastUsedDate
        result.tags = ["태그 \(rank)"]
        result.applicationName = "App \(rank)"
        return result
    }

    private func names(_ items: [DesktopItem]) -> [String] { items.map(\.name) }

    private func permutations(_ items: [DesktopItem]) -> [[DesktopItem]] {
        guard !items.isEmpty else { return [[]] }
        return items.indices.flatMap { index in
            var rest = items
            let first = rest.remove(at: index)
            return permutations(rest).map { [first] + $0 }
        }
    }
}
