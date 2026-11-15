import AppKit

@MainActor
final class DesktopAccess {
    private static let bookmarkKey = "desktopBookmark"
    private static let writableBookmarkKey = "desktopWritableBookmark"
    private let defaults: UserDefaults
    private var activeURL: URL?

    var hasBookmark: Bool { defaults.data(forKey: Self.bookmarkKey) != nil }

    private var hasWritableBookmark: Bool {
        // Another installed version can replace the shared bookmark with a read-only one.
        guard let bookmark = defaults.data(forKey: Self.bookmarkKey) else { return false }
        return defaults.data(forKey: Self.writableBookmarkKey) == bookmark
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    deinit {
        activeURL?.stopAccessingSecurityScopedResource()
    }

    func loadFolder() async throws -> DesktopSnapshot? {
        try await withFolderAccess { url in
            let items = try await Task.detached(priority: .userInitiated) {
                try DesktopItem.contents(of: url)
            }.value
            return (url, items)
        }
    }

    func chooseFolder() async throws -> DesktopSnapshot? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Connect Folder")
        panel.message = String(localized: "Choose a folder to open or share its items, or move them to the Trash after confirmation.")
        panel.prompt = String(localized: "Connect")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = activeURL ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        NSApp.activate(ignoringOtherApps: true)
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let url = panel.url else { return nil }

        // NSOpenPanel starts this scope; keep it only after the new connection succeeds.
        var connected = false
        defer {
            if !connected { url.stopAccessingSecurityScopedResource() }
        }
        guard url.isFileURL,
              try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw AccessError.invalidFolder
        }
        let items = try await Task.detached(priority: .userInitiated) {
            try DesktopItem.contents(of: url)
        }.value
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        saveBookmark(bookmark, writable: true)
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = url
        connected = true
        return (url, items)
    }

    func open(_ item: DesktopItem, in folder: URL) async throws {
        let result: Bool? = try await withFolderAccess { current in
            guard current.standardizedFileURL == folder.standardizedFileURL, item.isChild(of: current) else {
                throw AccessError.changedFolder
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                NSWorkspace.shared.open(item.url, configuration: .init()) { app, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if app != nil {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AccessError.openFailed)
                    }
                }
            }
            return true
        }
        guard result == true else { throw AccessError.permissionDenied }
    }

    func moveToTrash(_ items: [DesktopItem], in folder: URL) async throws {
        guard hasWritableBookmark else { throw AccessError.reconnectForTrash }
        let done = try await withFolderAccess { current in
            guard current.standardizedFileURL == folder.standardizedFileURL else { throw AccessError.changedFolder }
            try await Task.detached(priority: .userInitiated) {
                try Self.moveToTrash(items, within: current) { url in
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            }.value
            return true
        }
        guard done == true else { throw AccessError.permissionDenied }
    }

    nonisolated static func moveToTrash(_ items: [DesktopItem], within folder: URL,
                                        recycle: (URL) throws -> Void) throws {
        guard items.allSatisfy({ $0.isChild(of: folder) }) else { throw AccessError.changedFolder }
        var failures = 0
        var firstFailure: (String, Error)?
        for item in items {
            do {
                guard let identity = item.fileIdentity, identity == FileIdentity(item.url) else {
                    throw AccessError.changedItem
                }
                try recycle(item.url)
            } catch {
                if firstFailure == nil { firstFailure = (item.name, error) }
                failures += 1
            }
        }
        if let (name, error) = firstFailure {
            throw AccessError.trashFailed(failures, items.count, name, error.localizedDescription)
        }
    }

    private func withFolderAccess<T>(_ body: (URL) async throws -> T) async throws -> T? {
        guard let url = try restoreFolder() else { return nil }
        // An operation keeps its own scope while a new connection replaces activeURL.
        guard url.startAccessingSecurityScopedResource() else { throw AccessError.permissionDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        return try await body(url)
    }

    private func restoreFolder() throws -> URL? {
        if let activeURL { return activeURL }
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard url.isFileURL, url.startAccessingSecurityScopedResource() else {
            throw AccessError.permissionDenied
        }
        do {
            if stale {
                let writable = hasWritableBookmark
                let updated = try url.bookmarkData(
                    options: writable ? [.withSecurityScope] : [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                saveBookmark(updated, writable: writable)
            }
            activeURL = url
            return url
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    private func saveBookmark(_ data: Data, writable: Bool) {
        defaults.set(data, forKey: Self.bookmarkKey)
        if writable { defaults.set(data, forKey: Self.writableBookmarkKey) }
    }

    enum AccessError: LocalizedError {
        case invalidFolder, permissionDenied, changedFolder, openFailed, reconnectForTrash, changedItem
        case trashFailed(Int, Int, String, String)

        var errorDescription: String? {
            switch self {
            case .invalidFolder: return String(localized: "Choose a folder to connect.")
            case .permissionDenied: return String(localized: "Cannot access this folder. Please reconnect it.")
            case .changedFolder: return String(localized: "The connected folder has changed. Refresh the file list.")
            case .openFailed: return String(localized: "The file could not be opened in its default app.")
            case .reconnectForTrash: return String(localized: "Reconnect this folder once to allow moving items to the Trash.")
            case .changedItem: return String(localized: "This item has changed. Refresh the file list and select it again.")
            case let .trashFailed(failed, total, name, detail):
                return String(localized: "Could not move \(failed) of \(total) items to the Trash.\n\(name): \(detail)")
            }
        }
    }
}
