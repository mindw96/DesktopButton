import AppKit
import XCTest
@testable import OneButton

@MainActor
final class DesktopStoreTests: XCTestCase {
    func testDirectoryContentsAreShallowHiddenFilteredAndNaturallySorted() async throws {
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

        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let store = DesktopStore(defaults: defaults) { sort in
            (folder, try DesktopItem.contents(of: folder, for: sort))
        }
        await store.refresh()
        let items = store.items
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

        let disconnected = DesktopStore(defaults: defaults, loadFolder: { _ in nil })
        await disconnected.refresh()
        XCTAssertFalse(disconnected.hasConnection)
        XCTAssertNil(disconnected.folderURL)
        XCTAssertNil(disconnected.errorMessage)

        let empty = DesktopStore(defaults: defaults, loadFolder: { _ in (folder, []) })
        await empty.refresh()
        XCTAssertTrue(empty.hasConnection)
        XCTAssertEqual(empty.folderURL, folder)
        XCTAssertTrue(empty.items.isEmpty)
        XCTAssertNil(empty.errorMessage)

        let failed = DesktopStore(defaults: defaults, loadFolder: { _ in throw CocoaError(.fileReadNoPermission) })
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
        let store = DesktopStore(defaults: defaults) { _ in
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

    func testConnectedFolderTracksRenameAndRejectsAReplacementAcrossRelaunch() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = root.appendingPathComponent("connected", isDirectory: true)
        let renamed = root.appendingPathComponent("renamed", isDirectory: true)
        let moved = root.appendingPathComponent("elsewhere", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try Data().write(to: source.appendingPathComponent("original.txt"))
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let bookmark = try source.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        defaults.set(bookmark, forKey: "desktopBookmark")
        let access = DesktopAccess(defaults: defaults)
        let initial = try await access.loadFolder()
        XCTAssertEqual(initial?.items.map(\.name), ["original.txt"])

        try fm.moveItem(at: source, to: renamed)
        let afterRename = try await access.loadFolder()
        XCTAssertEqual(afterRename?.url.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(afterRename?.items.map(\.name), ["original.txt"])
        XCTAssertNil(defaults.data(forKey: "desktopWritableBookmark"))

        try fm.moveItem(at: renamed, to: moved)
        try fm.createDirectory(at: renamed, withIntermediateDirectories: false)
        try Data().write(to: renamed.appendingPathComponent("replacement.txt"))
        for service in [access, DesktopAccess(defaults: defaults)] {
            do {
                // Some filesystems resolve bookmarks by file ID even after the path is reused.
                let snapshot = try await service.loadFolder()
                XCTAssertEqual(snapshot?.items.map(\.name), ["original.txt"])
                XCTAssertEqual(snapshot?.url.standardizedFileURL, moved.standardizedFileURL)
            } catch DesktopAccess.AccessError.permissionDenied {
                XCTAssertTrue(service.hasBookmark)
            }
        }
    }

    func testUnmigratedBookmarkCannotAdoptAReplacementFolder() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let connected = root.appendingPathComponent("connected", isDirectory: true)
        let original = root.appendingPathComponent("original", isDirectory: true)
        try fm.createDirectory(at: connected, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let bookmark = try connected.bookmarkData(options: [.withSecurityScope])
        defaults.set(bookmark, forKey: "desktopBookmark")
        try fm.moveItem(at: connected, to: original)
        try fm.createDirectory(at: connected, withIntermediateDirectories: false)
        do {
            let snapshot = try await DesktopAccess(defaults: defaults).loadFolder()
            XCTAssertEqual(snapshot?.url.standardizedFileURL, original.standardizedFileURL)
        } catch DesktopAccess.AccessError.permissionDenied {
            XCTAssertEqual(defaults.data(forKey: "desktopBookmark"), bookmark)
        }
    }

    func testOpenAcceptsEditedFileButRejectsSameNameReplacementBeforeLaunch() async throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: folder) }
        let file = folder.appendingPathComponent("photo.txt")
        try Data("first".utf8).write(to: file)
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        defaults.set(try folder.bookmarkData(options: [.withSecurityScope]), forKey: "desktopBookmark")
        let access = DesktopAccess(defaults: defaults)
        let snapshot = try await access.loadFolder()
        let connected = try XCTUnwrap(snapshot?.url)
        let selected = try XCTUnwrap(snapshot?.items.first)
        let writer = try FileHandle(forWritingTo: file)
        try writer.write(contentsOf: Data("edit".utf8))
        try writer.close()
        var launches: [URL] = []
        try await access.open(selected, in: connected) { launches.append($0) }
        try fm.moveItem(at: file, to: folder.appendingPathComponent("original.txt"))
        try Data("replacement".utf8).write(to: file)
        do {
            try await access.open(selected, in: connected) { launches.append($0) }
            XCTFail("Replaced item was accepted")
        } catch DesktopAccess.AccessError.changedItem {}
        XCTAssertEqual(launches, [selected.url])
    }

    func testOpeningAnItemOutsideCurrentSnapshotIsRejected() async {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let store = DesktopStore(defaults: defaults, loadFolder: { _ in (URL(fileURLWithPath: "/test/Desktop"), []) })
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

    func testSortingChangesImmediatelyAndSurvivesRefreshAndRelaunch() async {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        defaults.set("grid", forKey: "desktopLayout")
        defaults.set(true, forKey: "showDockIcon")
        let bookmark = Data("keep existing connection".utf8)
        defaults.set(bookmark, forKey: "desktopBookmark")
        let folder = URL(fileURLWithPath: "/test/Desktop")
        let small = DesktopItem(url: folder.appendingPathComponent("10.txt"), name: "10.txt", isDirectory: false, size: 1)
        let large = DesktopItem(url: folder.appendingPathComponent("2.txt"), name: "2.txt", isDirectory: false, size: 20)
        let store = DesktopStore(defaults: defaults, loadFolder: { _ in (folder, [small, large]) })
        await store.refresh()
        XCTAssertEqual(store.items, [large, small])
        await store.setSortCriterion(.size)
        XCTAssertEqual(store.items, [small, large])
        store.sortDirection = .descending
        XCTAssertEqual(store.items, [large, small])
        await store.refresh()
        XCTAssertEqual(store.items, [large, small])

        let restored = DesktopStore(defaults: defaults, loadFolder: { _ in (folder, [small, large]) })
        await restored.refresh()
        XCTAssertEqual(restored.sortCriterion, .size)
        XCTAssertEqual(restored.sortDirection, .descending)
        XCTAssertEqual(restored.items, [large, small])
        XCTAssertEqual(defaults.data(forKey: "desktopBookmark"), bookmark)
        XCTAssertEqual(defaults.string(forKey: "desktopLayout"), "grid")
        XCTAssertTrue(defaults.bool(forKey: "showDockIcon"))
    }

    func testPendingRefreshUsesMostRecentSortChoice() async {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let folder = URL(fileURLWithPath: "/test/Desktop")
        let small = DesktopItem(url: folder.appendingPathComponent("a"), name: "a", isDirectory: false, size: 1)
        let large = DesktopItem(url: folder.appendingPathComponent("b"), name: "b", isDirectory: false, size: 2)
        var pending: CheckedContinuation<DesktopSnapshot?, Error>?
        var requests: [DesktopSort] = []
        let store = DesktopStore(defaults: defaults) { sort in
            requests.append(sort)
            if sort == .name {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return (folder, [small, large])
        }
        let refresh = Task { await store.refresh() }
        while pending == nil { await Task.yield() }
        store.sortDirection = .descending
        await store.setSortCriterion(.size)
        pending?.resume(returning: (folder, []))
        await refresh.value
        XCTAssertEqual(requests, [.name, .size])
        XCTAssertEqual(store.items, [large, small])
        await store.setSortCriterion(.name)
        XCTAssertEqual(requests, [.name, .size], "Names are present in every snapshot")
        XCTAssertFalse(store.isLoading)
    }

    func testDragKeepsSameFileAcrossSortMetadataChangesButRejectsReplacedParent() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("connected", isDirectory: true)
        let original = root.appendingPathComponent("original", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = folder.appendingPathComponent("sample.txt")
        try Data("sample".utf8).write(to: file)
        let store = DesktopStore(defaults: defaults) { sort in
            (folder, try DesktopItem.contents(of: folder, for: sort))
        }
        await store.refresh()
        let selected = try XCTUnwrap(store.items.first)
        await store.setSortCriterion(.size)
        XCTAssertEqual(store.dragURLs(for: [selected]), [file])

        try fm.moveItem(at: folder, to: original)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false)
        try fm.linkItem(at: original.appendingPathComponent("sample.txt"), to: file)
        XCTAssertEqual(FileIdentity(file), selected.fileIdentity)
        XCTAssertTrue(store.dragURLs(for: [selected]).isEmpty)
    }

    func testMissingOrInvalidSortPreferencesKeepExistingNameAscendingDefault() {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let fresh = DesktopStore(defaults: defaults, loadFolder: { _ in nil })
        XCTAssertEqual(fresh.sortCriterion, .name)
        XCTAssertEqual(fresh.sortDirection, .ascending)
        defaults.set("unknown-criterion", forKey: "desktopSort")
        defaults.set("unknown-direction", forKey: "desktopSortDirection")
        let restored = DesktopStore(defaults: defaults, loadFolder: { _ in nil })
        XCTAssertEqual(restored.sortCriterion, .name)
        XCTAssertEqual(restored.sortDirection, .ascending)
    }

    func testDirectoryReadLoadsRealMetadataWithoutCountingFolderOrPackageContents() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var file = folder.appendingPathComponent("sample.txt")
        let bytes = Data("sort metadata test".utf8)
        try bytes.write(to: file)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        let tags = ["테스트 10", "테스트 2"]
        if #available(macOS 26.0, *) {
            var values = URLResourceValues()
            values.tagNames = tags
            try file.setResourceValues(values)
        }
        for name in ["Folder", "Package.app"] {
            let directory = folder.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try Data(repeating: 1, count: 100).write(to: directory.appendingPathComponent("nested.txt"))
        }

        func fileItem(for sort: DesktopSort) throws -> DesktopItem {
            try XCTUnwrap(DesktopItem.contents(of: folder, for: sort).first { $0.url == file })
        }
        let basic = try fileItem(for: .name)
        XCTAssertNotNil(basic.fileIdentity)
        XCTAssertNil(basic.applicationName)
        XCTAssertNil(basic.lastUsedDate)
        XCTAssertNil(basic.size)
        XCTAssertNil(basic.modifiedDate)
        XCTAssertTrue(basic.tags.isEmpty)
        XCTAssertEqual(try fileItem(for: .size).size, bytes.count)
        XCTAssertEqual(try XCTUnwrap(fileItem(for: .modified).modifiedDate).timeIntervalSince1970,
                       modified.timeIntervalSince1970, accuracy: 1)
        XCTAssertNotNil(try fileItem(for: .created).createdDate)
        XCTAssertFalse(try XCTUnwrap(fileItem(for: .kind).kind).isEmpty)
        if #available(macOS 26.0, *) {
            XCTAssertEqual(Set(try fileItem(for: .tags).tags), Set(tags))
        }
        XCTAssertEqual(try fileItem(for: .application).applicationName, NSWorkspace.shared.urlForApplication(toOpen: file).map {
            FileManager.default.displayName(atPath: $0.path)
        })
        let items = try DesktopItem.contents(of: folder, for: .size)
        XCTAssertTrue(items.filter { $0.url != file }.allSatisfy { $0.size == nil })
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testLegacyConnectionCanStillShareAndRequiresReconnectBeforeTrash() async throws {
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("legacy.txt")
        let original = Data("keep me".utf8)
        try original.write(to: file)
        let legacy = try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess])
        defaults.set(legacy, forKey: "desktopBookmark")
        let store = DesktopStore(defaults: defaults)
        await store.refresh()
        let item = try XCTUnwrap(store.items.first)
        XCTAssertEqual(store.dragURLs(for: [item]).first?.standardizedFileURL, file.standardizedFileURL)

        // An older copy of the app may have selected a new folder since the last write grant.
        let unrelatedGrant = Data("old grant for another bookmark".utf8)
        defaults.set(unrelatedGrant, forKey: "desktopWritableBookmark")
        await store.moveToTrash([item])

        XCTAssertEqual(store.errorMessage, DesktopAccess.AccessError.reconnectForTrash.localizedDescription)
        XCTAssertNotNil(defaults.data(forKey: "desktopBookmark"))
        XCTAssertEqual(defaults.data(forKey: "desktopWritableBookmark"), unrelatedGrant)
        XCTAssertEqual(store.items.map(\.id), [item.id])
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testTrashRejectsOutsideItemBeforeMovingAnyAndNeverFollowsSymlinks() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("selection", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("outside.txt")
        let original = Data("not selected".utf8)
        try original.write(to: target)
        let link = folder.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let linkedItem = try XCTUnwrap(DesktopItem.contents(of: folder).first)
        let outsideItem = try XCTUnwrap(DesktopItem.contents(of: root).first { $0.name == "outside.txt" })

        XCTAssertThrowsError(try DesktopAccess.moveToTrash([linkedItem, outsideItem], within: folder) { _ in
            XCTFail("Outside item must reject the entire request")
        })
        let relocated = root.appendingPathComponent("recycled-link")
        try DesktopAccess.moveToTrash([linkedItem], within: folder) { url in
            XCTAssertEqual(url.standardizedFileURL, link.standardizedFileURL)
            try fm.moveItem(at: url, to: relocated)
        }
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: relocated.path), target.path)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    func testTrashSkipsHardLinkedItemWhenParentIsReplacedMidOperation() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let connected = root.appendingPathComponent("connected", isDirectory: true)
        let moved = root.appendingPathComponent("moved", isDirectory: true)
        try fm.createDirectory(at: connected, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for name in ["a", "b"] { try Data().write(to: connected.appendingPathComponent(name)) }
        let entries = try DesktopItem.contents(of: connected).sorted { $0.name < $1.name }
        var calls = 0
        XCTAssertThrowsError(try DesktopAccess.moveToTrash(entries, within: connected) { url in
            calls += 1
            guard calls == 1 else { return XCTFail("Recycled a hard link inside the replacement directory") }
            try fm.moveItem(at: url, to: root.appendingPathComponent("recycled"))
            try fm.moveItem(at: connected, to: moved)
            try fm.createDirectory(at: connected, withIntermediateDirectories: false)
            try fm.linkItem(at: moved.appendingPathComponent("b"), to: connected.appendingPathComponent("b"))
        }) { error in
            guard case DesktopAccess.AccessError.trashFailed(1, 2, _, _) = error else {
                return XCTFail("Expected partial failure, got \(error)")
            }
        }
        XCTAssertEqual(calls, 1)
    }

    func testTrashSkipsReplacedMissingAndLockedItemsAndReportsPartialResult() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("selection", isDirectory: true)
        let recycleBin = root.appendingPathComponent("test-recycle", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: recycleBin, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let names = ["file", "missing", "locked", "replaced"]
        for name in names { try Data(name.utf8).write(to: folder.appendingPathComponent(name)) }
        let child = folder.appendingPathComponent("subfolder", isDirectory: true)
        try fm.createDirectory(at: child, withIntermediateDirectories: false)
        try Data("nested".utf8).write(to: child.appendingPathComponent("child"))
        let selection = try DesktopItem.contents(of: folder)
        try fm.moveItem(at: folder.appendingPathComponent("replaced"), to: root.appendingPathComponent("old"))
        try Data("replacement".utf8).write(to: folder.appendingPathComponent("replaced"))
        try fm.removeItem(at: folder.appendingPathComponent("missing"))

        XCTAssertThrowsError(try DesktopAccess.moveToTrash(selection, within: folder) { url in
            if url.lastPathComponent == "locked" { throw CocoaError(.fileWriteNoPermission) }
            try fm.moveItem(at: url, to: recycleBin.appendingPathComponent(url.lastPathComponent))
        }) { error in
            guard case DesktopAccess.AccessError.trashFailed(3, 5, _, _) = error else {
                return XCTFail("Expected three reported failures, got \(error)")
            }
        }
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: folder.path)), ["locked", "replaced"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("replaced")), Data("replacement".utf8))
        XCTAssertEqual(try Data(contentsOf: recycleBin.appendingPathComponent("subfolder/child")), Data("nested".utf8))
        XCTAssertEqual(try Data(contentsOf: recycleBin.appendingPathComponent("file")), Data("file".utf8))
    }

    private var defaultsSuite = ""

    private func isolatedDefaults() -> UserDefaults {
        defaultsSuite = "OneButton.Tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: defaultsSuite)!
    }
}
