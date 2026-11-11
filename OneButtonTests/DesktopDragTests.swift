import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import OneButton

@MainActor
final class DesktopDragTests: XCTestCase {
    func testFileDragExportsOriginalBytesURLAndFilenameWithoutChangingSource() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let file = folder.appendingPathComponent("첨부 파일 1.txt")
        let original = Data("Folder In Bar drag attachment\n한글 파일 내용".utf8)
        try original.write(to: file)
        let items = try DesktopItem.contents(of: folder)
        let store = DesktopStore(defaults: defaults, loadFolder: { (folder, items) })
        await store.refresh()

        let provider = store.dragProvider(for: try XCTUnwrap(items.first))
        XCTAssertEqual(provider.suggestedName, file.lastPathComponent)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier))
        let received = try await exportedData(from: provider, type: .plainText)
        let receivedURL = try await exportedURL(from: provider)
        XCTAssertEqual(received, original)
        XCTAssertEqual(receivedURL.standardizedFileURL, file.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertNil(store.openingURL)
        XCTAssertNil(store.errorMessage)
    }

    func testStaleAndOutsideFolderItemsCannotExportFiles() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let previousFolder = folder.appendingPathComponent("previous", isDirectory: true)
        let currentFolder = folder.appendingPathComponent("current", isDirectory: true)
        try FileManager.default.createDirectory(at: previousFolder, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: currentFolder, withIntermediateDirectories: false)
        let file = previousFolder.appendingPathComponent("still exists.txt")
        try Data("original".utf8).write(to: file)
        let oldItems = try DesktopItem.contents(of: previousFolder)
        let item = try XCTUnwrap(oldItems.first)
        var snapshot: DesktopSnapshot = (previousFolder, oldItems)
        let store = DesktopStore(defaults: defaults, loadFolder: { snapshot })
        await store.refresh()
        snapshot = (currentFolder, [])
        await store.refresh()

        XCTAssertTrue(store.dragProvider(for: item).registeredTypeIdentifiers.isEmpty)
        XCTAssertNotNil(store.errorMessage)

        // Even an inconsistent snapshot must not export an item from another folder.
        snapshot = (currentFolder, oldItems)
        await store.refresh()
        XCTAssertTrue(store.dragProvider(for: item).registeredTypeIdentifiers.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original")
    }

    func testFileDeletedAfterRefreshCannotBeDragged() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let file = folder.appendingPathComponent("removed.txt")
        try Data("temporary".utf8).write(to: file)
        let items = try DesktopItem.contents(of: folder)
        let store = DesktopStore(defaults: defaults, loadFolder: { (folder, items) })
        await store.refresh()
        try FileManager.default.removeItem(at: file)

        let provider = store.dragProvider(for: try XCTUnwrap(items.first))
        XCTAssertTrue(provider.registeredTypeIdentifiers.isEmpty)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.openingURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testFolderDragExportsUsableURLAndPreservesContents() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let child = folder.appendingPathComponent("공유 자료", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
        let nestedFile = child.appendingPathComponent("original.txt")
        let original = Data("keep this file".utf8)
        try original.write(to: nestedFile)
        let items = try DesktopItem.contents(of: folder)
        let store = DesktopStore(defaults: defaults, loadFolder: { (folder, items) })
        await store.refresh()

        let provider = store.dragProvider(for: try XCTUnwrap(items.first))
        XCTAssertEqual(provider.suggestedName, child.lastPathComponent)
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        let receivedURL = try await exportedURL(from: provider)
        XCTAssertEqual(receivedURL.standardizedFileURL, child.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: receivedURL.appendingPathComponent("original.txt")), original)
        XCTAssertEqual(try Data(contentsOf: nestedFile), original)
        XCTAssertNil(store.errorMessage)
    }

    private var defaultsSuite = ""

    private func isolatedDefaults() -> UserDefaults {
        defaultsSuite = "OneButton.DragTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: defaultsSuite)!
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func exportedURL(from provider: NSItemProvider) async throws -> URL {
        let data = try await exportedData(from: provider, type: .fileURL)
        let string = try XCTUnwrap(String(data: data, encoding: .utf8))
        return try XCTUnwrap(URL(string: string))
    }

    private func exportedData(from provider: NSItemProvider, type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
