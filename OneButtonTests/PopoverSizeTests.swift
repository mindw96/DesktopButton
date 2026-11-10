import XCTest
@testable import OneButton

@MainActor
final class PopoverSizeTests: XCTestCase {
    func testSizePersistsAndRestoresInTheProvidedDefaults() {
        let suite = "OneButton.SizeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let size = PopoverSize(defaults: defaults)
        XCTAssertEqual(size.size, CGSize(width: 340, height: 440))
        size.resize(to: CGSize(width: 500, height: 540))
        size.save()
        XCTAssertEqual(PopoverSize(defaults: defaults).size, CGSize(width: 500, height: 540))
    }

    func testMinimumMaximumAndScreenBounds() {
        let screen = CGSize(width: 800, height: 600)
        XCTAssertEqual(PopoverSize.clamped(CGSize(width: 100, height: 100), available: screen),
                       CGSize(width: 300, height: 260))
        XCTAssertEqual(PopoverSize.clamped(CGSize(width: 1800, height: 1800), available: screen), screen)
        XCTAssertEqual(PopoverSize.clamped(CGSize(width: 1800, height: 1800),
                                          available: CGSize(width: 2200, height: 2200)),
                       CGSize(width: 960, height: 900))
        XCTAssertEqual(PopoverSize.clamped(CGSize(width: 500, height: 500),
                                          available: CGSize(width: 200, height: 180)),
                       CGSize(width: 200, height: 180))
    }

    func testInvalidSavedDimensionsUseFiniteDefaults() {
        XCTAssertEqual(PopoverSize.clamped(CGSize(width: CGFloat.nan, height: CGFloat.infinity),
                                          available: PopoverSize.maximumSize), PopoverSize.defaultSize)
    }

    func testScreenCoordinateDragSupportsBothCorners() {
        let size = CGSize(width: 340, height: 440)
        let start = CGPoint(x: 500, y: 500)
        XCTAssertEqual(PopoverSize.draggedSize(from: size, start: start, current: CGPoint(x: 340, y: 400),
                                              fromLeadingEdge: true), CGSize(width: 500, height: 540))
        XCTAssertEqual(PopoverSize.draggedSize(from: size, start: start, current: CGPoint(x: 660, y: 400),
                                              fromLeadingEdge: false), CGSize(width: 500, height: 540))
        XCTAssertEqual(PopoverSize.draggedSize(from: size, start: start, current: CGPoint(x: 560, y: 560),
                                              fromLeadingEdge: true), CGSize(width: 280, height: 380))
    }
}
