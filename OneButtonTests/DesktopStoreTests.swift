import XCTest
@testable import OneButton

@MainActor
final class DesktopStoreTests: XCTestCase {
    func testDirectoryContentsAreShallowHiddenFilteredAndNaturallySorted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["문서 10.txt", "문서 2.txt", ".hidden"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }
        let subfolder = folder.appendingPathComponent("자료")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: false)
        try Data().write(to: subfolder.appendingPathComponent("nested.txt"))
        let package = folder.appendingPathComponent("Sample.app")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)

        let items = try DesktopItem.contents(of: folder)
        XCTAssertEqual(Set(items.map(\.name)), Set(["문서 2.txt", "문서 10.txt", "자료", "Sample.app"]))
        XCTAssertLessThan(items.firstIndex { $0.name == "문서 2.txt" }!, items.firstIndex { $0.name == "문서 10.txt" }!)
        XCTAssertEqual(items.first { $0.name == "자료" }?.isDirectory, true)
        XCTAssertEqual(items.first { $0.name == "Sample.app" }?.isDirectory, false)
    }

    func testMissingDirectoryThrowsInsteadOfReturningAnEmptyList() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try DesktopItem.contents(of: missing))
    }

    func testDisconnectedEmptyAndFailedStatesRemainDistinct() async {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let folder = URL(fileURLWithPath: "/test/Desktop")

        let disconnected = DesktopStore(defaults: defaults, loadFolder: { nil })
        await disconnected.refresh()
        XCTAssertFalse(disconnected.hasConnection)
        XCTAssertNil(disconnected.folderURL)
        XCTAssertNil(disconnected.errorMessage)

        let empty = DesktopStore(defaults: defaults, loadFolder: { (folder, []) })
        await empty.refresh()
        XCTAssertTrue(empty.hasConnection)
        XCTAssertEqual(empty.folderURL, folder)
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertNil(empty.errorMessage)

        let failed = DesktopStore(defaults: defaults, loadFolder: { throw CocoaError(.fileReadNoPermission) })
        await failed.refresh()
        XCTAssertNil(failed.folderURL)
        XCTAssertNotNil(failed.errorMessage)
        XCTAssertFalse(failed.isLoading)
        failed.dismissError()
        XCTAssertNil(failed.errorMessage)
        XCTAssertNil(failed.folderURL)
        XCTAssertTrue(failed.items.isEmpty)
    }

    func testLateRefreshCannotReplaceNewerResults() async {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        var requests: [CheckedContinuation<DesktopSnapshot?, Error>] = []
        let store = DesktopStore(defaults: defaults) {
            try await withCheckedThrowingContinuation { requests.append($0) }
        }

        let first = Task { await store.refresh() }
        while requests.count < 1 { await Task.yield() }
        let second = Task { await store.refresh() }
        while requests.count < 2 { await Task.yield() }

        let oldFolder = URL(fileURLWithPath: "/old/Desktop")
        let newFolder = URL(fileURLWithPath: "/new/Desktop")
        let latest = DesktopItem(url: newFolder.appendingPathComponent("new.txt"), name: "new.txt", isDirectory: false)
        requests[1].resume(returning: (newFolder, [latest]))
        await second.value
        requests[0].resume(returning: (oldFolder, []))
        await first.value

        XCTAssertEqual(store.folderURL, newFolder)
        XCTAssertEqual(store.items, [latest])
        XCTAssertFalse(store.isLoading)
    }

    func testBrokenBookmarkKeepsReconnectState() async {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        defaults.set(Data("invalid bookmark".utf8), forKey: "desktopBookmark")
        let store = DesktopStore(defaults: defaults)
        await store.refresh()
        XCTAssertTrue(store.hasConnection)
        XCTAssertNil(store.folderURL)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNotNil(defaults.data(forKey: "desktopBookmark"))
    }

    func testOpeningAnItemOutsideCurrentSnapshotIsRejected() async {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let store = DesktopStore(defaults: defaults, loadFolder: { (URL(fileURLWithPath: "/test/Desktop"), []) })
        await store.refresh()
        let stale = DesktopItem(url: URL(fileURLWithPath: "/other/file.txt"), name: "file.txt", isDirectory: false)
        let result = await store.open(stale)
        XCTAssertFalse(result)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.openingURL)
        await store.refresh()
        XCTAssertNotNil(store.errorMessage)
        store.dismissError()
        XCTAssertNil(store.errorMessage)
    }

    private var defaultsSuite = ""

    private func isolatedDefaults() -> UserDefaults {
        defaultsSuite = "OneButton.Tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: defaultsSuite)!
    }
}
