import SwiftUI
import XCTest
@testable import OneButton

final class DesktopLayoutTests: XCTestCase {
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
