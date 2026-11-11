import SwiftUI
import XCTest
@testable import OneButton

final class DesktopLayoutTests: XCTestCase {
    func testResizedGridUsesMatchingColumnsForKeyboardNavigation() {
        XCTAssertEqual(DesktopLayout.columnCount(for: 300), 2)
        XCTAssertEqual(DesktopLayout.columnCount(for: 340), 3)
        XCTAssertEqual(DesktopLayout.columnCount(for: 500), 4)
        XCTAssertEqual(DesktopLayout.columnCount(for: 700), 6)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 1, direction: .down, itemCount: 10,
                                                         columnCount: 4), 5)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 8, direction: .up, itemCount: 10,
                                                         columnCount: 4), 4)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 7, direction: .down, itemCount: 10,
                                                         columnCount: 4), 9)
    }

    func testIconSizesPreserveDefaultDimensionsAndAdjustGridDensity() {
        XCTAssertEqual(DesktopIconSize.medium.gridSize, 48)
        XCTAssertEqual(DesktopIconSize.medium.listSize, 24)
        XCTAssertEqual(DesktopLayout.columnCount(for: 500, iconSize: .small), 5)
        XCTAssertEqual(DesktopLayout.columnCount(for: 500, iconSize: .medium), 4)
        XCTAssertEqual(DesktopLayout.columnCount(for: 500, iconSize: .large), 3)
        for width in [CGFloat(300), 340, 500, 700, 960] {
            let small = DesktopLayout.columnCount(for: width, iconSize: .small)
            let medium = DesktopLayout.columnCount(for: width, iconSize: .medium)
            let large = DesktopLayout.columnCount(for: width, iconSize: .large)
            XCTAssertGreaterThanOrEqual(small, medium)
            XCTAssertGreaterThanOrEqual(medium, large)
            XCTAssertEqual(DesktopLayout.columnCount(for: width), medium)
        }
    }

    func testLargeIconsKeepAUsableColumnCountAtNarrowWidths() {
        XCTAssertEqual(DesktopLayout.columnCount(for: 300, iconSize: .large), 2)
        XCTAssertEqual(DesktopLayout.columnCount(for: 100, iconSize: .large), 1)
        XCTAssertEqual(DesktopLayout.columnCount(for: 0, iconSize: .large), 1)
        for size in DesktopIconSize.allCases {
            XCTAssertGreaterThan(size.listSize, 0)
            XCTAssertLessThan(size.listSize, size.gridSize)
        }
    }

    func testIconSizeColumnsKeepKeyboardNavigationInsideAnIncompleteLastRow() {
        for size in DesktopIconSize.allCases {
            let columns = DesktopLayout.columnCount(for: 500, iconSize: size)
            let count = columns + 1
            XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: columns - 1, direction: .down,
                                                             itemCount: count, columnCount: columns), columns)
            XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: columns, direction: .down,
                                                             itemCount: count, columnCount: columns), columns)
            XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: columns, direction: .up,
                                                             itemCount: count, columnCount: columns), 0)
        }
    }

    func testGridArrowsFollowRowsAndColumns() {
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 1, direction: .down, itemCount: 8), 4)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 7, direction: .up, itemCount: 8), 4)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 4, direction: .left, itemCount: 8), 3)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 4, direction: .right, itemCount: 8), 5)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 2, direction: .right, itemCount: 8), 3)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 3, direction: .left, itemCount: 8), 2)
    }

    func testGridBoundariesAndIncompleteLastRow() {
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 2, direction: .up, itemCount: 8), 2)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 0, direction: .left, itemCount: 8), 0)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 7, direction: .right, itemCount: 8), 7)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 5, direction: .down, itemCount: 8), 7)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 6, direction: .down, itemCount: 8), 6)
        XCTAssertEqual(DesktopLayout.grid.selectionIndex(from: 7, direction: .down, itemCount: 8), 7)
    }

    func testListKeepsSingleRowNavigationAndIgnoresHorizontalArrows() {
        XCTAssertEqual(DesktopLayout.list.selectionIndex(from: 3, direction: .down, itemCount: 8), 4)
        XCTAssertEqual(DesktopLayout.list.selectionIndex(from: 3, direction: .up, itemCount: 8), 2)
        XCTAssertEqual(DesktopLayout.list.selectionIndex(from: 3, direction: .left, itemCount: 8), 3)
        XCTAssertEqual(DesktopLayout.list.selectionIndex(from: 3, direction: .right, itemCount: 8), 3)
        XCTAssertEqual(DesktopLayout.list.selectionIndex(from: 0, direction: .up, itemCount: 8), 0)
        XCTAssertEqual(DesktopLayout.list.selectionIndex(from: 7, direction: .down, itemCount: 8), 7)
    }

    func testEmptyMissingAndStaleSelectionStayInBounds() {
        for layout in [DesktopLayout.list, .grid] {
            XCTAssertNil(layout.selectionIndex(from: 0, direction: .down, itemCount: 0))
            XCTAssertEqual(layout.selectionIndex(from: nil, direction: .down, itemCount: 5), 0)
            XCTAssertEqual(layout.selectionIndex(from: 8, direction: .up, itemCount: 5), 0)
            XCTAssertEqual(layout.selectionIndex(from: 0, direction: .down, itemCount: 1), 0)
        }
    }
}
