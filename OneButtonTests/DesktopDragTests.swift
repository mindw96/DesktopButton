import AppKit
import XCTest
@testable import OneButton

@MainActor
final class DesktopDragTests: XCTestCase {
    func testMultiDragPublishesIndependentFileURLsInOrderAndPreservesOriginalBytes() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("1. 첨부.txt")
        let second = folder.appendingPathComponent("2. 첨부.dat")
        try Data("한글 메모".utf8).write(to: first)
        try Data([0, 5, 8]).write(to: second)
        let items = try DesktopItem.contents(of: folder)
        let store = makeStore { (folder, items) }
        await store.refresh()

        let draggingItems = FilePointerSurface.draggingItems(for: store.dragURLs(for: store.items), at: .zero)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let writers = try draggingItems.map { try XCTUnwrap($0.item as? NSPasteboardWriting) }
        XCTAssertTrue(pasteboard.writeObjects(writers))
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
        let received = try XCTUnwrap(pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])
        XCTAssertEqual(received.map(\.standardizedFileURL), [first, second].map(\.standardizedFileURL))
        XCTAssertEqual(try received.map { try Data(contentsOf: $0) }, [Data("한글 메모".utf8), Data([0, 5, 8])])
        XCTAssertNil(store.openingURL)
        XCTAssertNil(store.errorMessage)
    }

    func testMixedSelectionWithDeletedItemCannotStartAPartialDrag() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("keep.txt")
        let missing = folder.appendingPathComponent("removed.txt")
        try Data("original".utf8).write(to: first)
        try Data().write(to: missing)
        let items = try DesktopItem.contents(of: folder)
        let store = makeStore { (folder, items) }
        await store.refresh()
        try FileManager.default.removeItem(at: missing)

        XCTAssertTrue(store.dragURLs(for: items).isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try Data(contentsOf: first), Data("original".utf8))
    }

    func testStaleAndOutOfFolderSelectionsCannotStartDrag() async throws {
        let previous = try makeFolder()
        let current = try makeFolder()
        defer {
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.removeItem(at: current)
        }
        try Data().write(to: previous.appendingPathComponent("old.txt"))
        let stale = try DesktopItem.contents(of: previous)
        var snapshot = (previous, stale)
        let store = makeStore { snapshot }
        await store.refresh()
        snapshot = (current, [])
        await store.refresh()
        XCTAssertTrue(store.dragURLs(for: stale).isEmpty)

        snapshot = (current, stale)
        await store.refresh()
        XCTAssertTrue(store.dragURLs(for: stale).isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    func testFolderDragPreservesNestedFiles() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let child = folder.appendingPathComponent("공유 자료", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let nested = child.appendingPathComponent("original.txt")
        try Data("keep".utf8).write(to: nested)
        let items = try DesktopItem.contents(of: folder)
        let store = makeStore { (folder, items) }
        await store.refresh()

        XCTAssertEqual(store.dragURLs(for: items), [child])
        XCTAssertEqual(try Data(contentsOf: nested), Data("keep".utf8))
    }

    func testCommandShiftAndRefreshPreserveSelectionByFileIdentityAndDisplayOrder() throws {
        let items = try makeItems(["A", "B", "C", "D"])
        let keys = try items.map { try XCTUnwrap($0.selectionKey) }
        var selection = DesktopSelection()
        selection.select(items[0], modifiers: [], in: items)
        selection.select(items[2], modifiers: .command, in: items)
        XCTAssertEqual(selection.ids, [keys[0], keys[2]])
        selection.select(items[0], modifiers: .command, in: items)
        XCTAssertEqual(selection.ids, [keys[2]])
        selection.select(items[0], modifiers: .shift, in: items)
        XCTAssertEqual(selection.ids, Set(keys.prefix(3)))
        selection.select(items[3], modifiers: .shift, in: items.reversed())
        XCTAssertEqual(selection.ids, [keys[2], keys[3]])
        selection.selectAll(in: items)
        XCTAssertEqual(selection.ids, Set(keys))
        selection.reconcile(with: Array(items.prefix(2)))
        XCTAssertEqual(selection.ids, Set(keys.prefix(2)))
        XCTAssertNotNil(selection.lead)
    }

    func testRefreshDropsReplacedFileAndPreservesInPlaceEditsAndRangeAnchor() throws {
        let original = try makeItems(["A", "B", "C"])
        let folder = original[0].url.deletingLastPathComponent()
        var selection = DesktopSelection()
        selection.select(original[0], modifiers: [], in: original)
        selection.select(original[1], modifiers: .command, in: original)

        try Data("edited".utf8).write(to: original[0].url)
        try Data("replacement".utf8).write(to: original[1].url, options: .atomic)
        let updated = try DesktopItem.contents(of: folder).sorted { $0.name < $1.name }
        XCTAssertEqual(original[0].fileIdentity, updated[0].fileIdentity)
        XCTAssertNotEqual(original[1].fileIdentity, updated[1].fileIdentity)
        XCTAssertFalse(selection.contains(updated[1]))
        selection.reconcile(with: updated)
        XCTAssertEqual(updated.filter(selection.contains).map(\.url), [original[0].url])
        XCTAssertEqual(selection.lead, updated[0].selectionKey)

        selection.select(updated[2], modifiers: .shift, in: updated)
        XCTAssertEqual(selection.ids, Set(updated.compactMap(\.selectionKey)))
    }

    func testMarqueeSelectionRecalculatesFromMouseDownWhenTheBoxShrinks() throws {
        let items = try makeItems(["A", "B", "C"])
        let keys = try items.map { try XCTUnwrap($0.selectionKey) }
        let a = keys[0], b = keys[1], c = keys[2]
        var original = DesktopSelection()
        original.select(items[0], modifiers: [], in: items)
        original.select(items[2], modifiers: .command, in: items)

        XCTAssertEqual(original.marquee(hits: [b], modifiers: [], in: items).ids, [b])
        XCTAssertTrue(original.marquee(hits: [], modifiers: [], in: items).ids.isEmpty)
        XCTAssertEqual(original.marquee(hits: [a, b], modifiers: .shift, in: items).ids, [a, b, c])
        XCTAssertEqual(original.marquee(hits: [a, b], modifiers: .command, in: items).ids, [b, c])
        XCTAssertEqual(original.marquee(hits: [b], modifiers: .command, in: items).ids, [a, b, c])
        XCTAssertEqual(original.marquee(hits: [], modifiers: .command, in: items).ids, [a, c])
        XCTAssertEqual(original.ids, [a, c])
    }

    func testRemovedRowDiscardsPendingClickAndContextMenuAction() throws {
        let frame = NSRect(x: 0, y: 0, width: 100, height: 40)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: true)
        let row = FilePointerSurface.PointerView(frame: frame)
        var clicks = 0
        var trashRequests = 0
        row.actions = FilePointerSurface(clicked: { _, _ in clicks += 1 }, dragURLs: { _ in [] },
                                         showContext: {}, requestTrash: { trashRequests += 1 })
        window.contentView?.addSubview(row)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10, y: 10),
                                                   modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        row.mouseDown(with: down)
        let menuItem = try XCTUnwrap(row.menu(for: down)?.items.first)
        row.removeFromSuperview()
        row.mouseUp(with: down)
        NSApp.sendAction(try XCTUnwrap(menuItem.action), to: menuItem.target, from: menuItem)
        XCTAssertEqual(clicks, 0)
        XCTAssertEqual(trashRequests, 0)
    }

    func testBulkDragLimitsPileArtworkAndKeepsAllFileURLsInOrder() throws {
        let items = try makeItems((0..<20).map { "document-\($0).txt" })
        let urls = items.map(\.url)
        let drag = FilePointerSurface.draggingItems(for: urls, at: .zero)
        XCTAssertEqual(drag.compactMap { $0.item as? URL }, urls)
        let visible = drag.filter { item in item.imageComponents?.contains { $0.contents != nil } == true }
        XCTAssertEqual(visible.count, 3)
    }

    func testMarqueeInGridSelectsPartiallyCoveredTilesInEitherDirection() {
        let grid = DesktopMarqueeLayout(layout: .grid, iconSize: .medium, columnCount: 3)
        let start = CGPoint(x: 210, y: 165), end = CGPoint(x: 160, y: 80)
        for (from, to) in [(start, end), (end, start)] {
            let box = DesktopMarqueeLayout.rectangle(from: from, to: to)
            XCTAssertEqual(grid.intersectingIndices(box, width: 320, itemCount: 5), [1, 4])
        }
        for empty in [CGRect(x: 108, y: 30, width: 2, height: 10),   // column gap
                      CGRect(x: 40, y: 113, width: 10, height: 2),    // row gap
                      CGRect(x: 250, y: 140, width: 10, height: 10),  // unfilled last cell
                      CGRect(x: 40, y: 30, width: 0, height: 10)] {
            XCTAssertTrue(grid.intersectingIndices(empty, width: 320, itemCount: 5).isEmpty)
        }
    }

    func testListMarqueeCanStartInTheGutterAndReachRowsBelowTheViewport() {
        let list = DesktopMarqueeLayout(layout: .list, iconSize: .large, columnCount: 1)
        let gutter = CGRect(x: 3, y: 2545, width: 5, height: 45)
        XCTAssertTrue(list.intersectingIndices(gutter, width: 300, itemCount: 100).isEmpty)
        // At the large icon size, this crosses the left edge of rows 65 and 66.
        let box = DesktopMarqueeLayout.rectangle(from: CGPoint(x: 25, y: 2590),
                                                  to: CGPoint(x: 3, y: 2545))
        XCTAssertEqual(list.intersectingIndices(box, width: 300, itemCount: 100), [65, 66])
        XCTAssertTrue(list.intersectingIndices(box, width: 300, itemCount: 20).isEmpty)
    }

    private func makeStore(load: @escaping () async throws -> DesktopSnapshot?) -> DesktopStore {
        let suite = "OneButton.DragTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return DesktopStore(defaults: defaults, loadFolder: { _ in try await load() })
    }

    private func makeItems(_ names: [String]) throws -> [DesktopItem] {
        let folder = try makeFolder()
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        for name in names { try Data().write(to: folder.appendingPathComponent(name)) }
        return try DesktopItem.contents(of: folder).sorted { $0.name < $1.name }
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}
