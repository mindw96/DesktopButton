import AppKit

@MainActor
final class DesktopAccess {
    private static let bookmarkKey = "desktopBookmark"
    private static let writableBookmarkKey = "desktopWritableBookmark"
    private static let folderIdentityKey = "desktopFolderIdentity"
    private let defaults: UserDefaults
    private var active: (url: URL, bookmark: Data, identity: String)?

    var connectedFolderIdentity: String? { active?.identity }
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
        active?.url.stopAccessingSecurityScopedResource()
    }

    func loadFolder(for sort: DesktopSort = .name) async throws -> DesktopSnapshot? {
        try await withFolderAccess { url, identity in
            try await Self.snapshot(of: url, identity: identity, sort: sort)
        }
    }

    private static func snapshot(of url: URL, identity: String, sort: DesktopSort) async throws -> DesktopSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let items = try DesktopItem.contents(of: url, for: sort)
            guard folderIdentity(at: url) == identity else { throw AccessError.permissionDenied }
            return (url, items)
        }.value
    }

    func chooseFolder(for sort: DesktopSort = .name) async throws -> DesktopSnapshot? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Connect Folder")
        panel.message = String(localized: "Choose a folder to open or share its items, or move them to the Trash after confirmation.")
        panel.prompt = String(localized: "Connect")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = active?.url ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

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
        guard let identity = Self.folderIdentity(at: url) else { throw AccessError.invalidFolder }
        let snapshot = try await Self.snapshot(of: url, identity: identity, sort: sort)
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard Self.folderIdentity(at: url) == identity else { throw AccessError.changedFolder }
        saveBookmark(bookmark, writable: true, identity: identity)
        active?.url.stopAccessingSecurityScopedResource()
        active = (url, bookmark, identity)
        connected = true
        return snapshot
    }

    func open(_ item: DesktopItem, in folder: URL,
              launch: (URL) async throws -> Void = openWithWorkspace) async throws {
        let result: Bool? = try await withFolderAccess { current, _ in
            guard current.standardizedFileURL == folder.standardizedFileURL, item.isChild(of: current) else {
                throw AccessError.changedFolder
            }
            guard let identity = item.fileIdentity, identity == FileIdentity(item.url) else {
                throw AccessError.changedItem
            }
            try await launch(item.url)
            return true
        }
        guard result == true else { throw AccessError.permissionDenied }
    }

    private static func openWithWorkspace(_ url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open(url, configuration: .init()) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if app != nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: AccessError.openFailed)
                }
            }
        }
    }

    func moveToTrash(_ items: [DesktopItem], in folder: URL) async throws {
        guard hasWritableBookmark else { throw AccessError.reconnectForTrash }
        let done = try await withFolderAccess { current, identity in
            guard current.standardizedFileURL == folder.standardizedFileURL else { throw AccessError.changedFolder }
            try await Task.detached(priority: .userInitiated) {
                try Self.moveToTrash(items, within: current, expectedFolder: identity) { url in
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            }.value
            return true
        }
        guard done == true else { throw AccessError.permissionDenied }
    }

    nonisolated static func moveToTrash(_ items: [DesktopItem], within folder: URL, expectedFolder: String? = nil,
                                        recycle: (URL) throws -> Void) throws {
        guard let directory = FileIdentity(folder, followingSymlinks: true),
              expectedFolder == nil || expectedFolder == folderIdentity(at: folder),
              items.allSatisfy({ $0.isChild(of: folder) }) else { throw AccessError.changedFolder }
        var failures = 0
        var firstFailure: (String, Error)?
        for item in items {
            do {
                guard directory == FileIdentity(folder, followingSymlinks: true) else { throw AccessError.changedFolder }
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

    private func withFolderAccess<T>(_ body: (URL, String) async throws -> T) async throws -> T? {
        try restoreFolder()
        guard let active else { return nil }
        // An operation keeps its own scope while a new connection replaces the active one.
        guard active.url.startAccessingSecurityScopedResource() else { throw AccessError.permissionDenied }
        defer { active.url.stopAccessingSecurityScopedResource() }
        return try await body(active.url, active.identity)
    }

    private func restoreFolder() throws {
        let data = defaults.data(forKey: Self.bookmarkKey)
        if let active, active.bookmark == data, Self.folderIdentity(at: active.url) == active.identity { return }
        active?.url.stopAccessingSecurityScopedResource()
        active = nil
        guard let data else { return }
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
            guard let identity = Self.folderIdentity(at: url) else { throw AccessError.permissionDenied }
            let record = defaults.dictionary(forKey: Self.folderIdentityKey)
            if record?["bookmark"] as? Data == data {
                guard record?["identity"] as? String == identity else { throw AccessError.permissionDenied }
            } else {
                // Older bookmarks have no saved inode. A stale one can resolve to a replacement at the old path.
                guard !stale, Self.matchesLegacyBookmark(data, at: url) else { throw AccessError.permissionDenied }
            }
            var bookmark = data
            if stale {
                let writable = hasWritableBookmark
                bookmark = try url.bookmarkData(
                    options: writable ? [.withSecurityScope] : [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                saveBookmark(bookmark, writable: writable, identity: identity)
            } else if record?["bookmark"] as? Data != data {
                remember(identity, for: bookmark)
            }
            active = (url, bookmark, identity)
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    nonisolated static func folderIdentity(at url: URL) -> String? {
        var info = stat()
        guard url.isFileURL, stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { return nil }
        // Use the persistent volume UUID across disk remounts when the filesystem supplies it.
        let path = URL(fileURLWithPath: url.path, isDirectory: true).resolvingSymlinksInPath()
        let uuid = try? path.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        if let uuid { return "\(uuid):\(info.st_ino)" }
        // A mount without a UUID may reuse a device number; also check the directory's birth time.
        return "device-\(info.st_dev):\(info.st_ino):\(info.st_birthtimespec.tv_sec):\(info.st_birthtimespec.tv_nsec)"
    }

    private static func matchesLegacyBookmark(_ data: Data, at url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeUUIDStringKey, .creationDateKey]
        let saved = URL.resourceValues(forKeys: keys, fromBookmarkData: data)
        let current = try? URL(fileURLWithPath: url.path, isDirectory: true).resourceValues(forKeys: keys)
        if let volume = saved?.volumeUUIDString, volume != current?.volumeUUIDString { return false }
        if let creation = saved?.creationDate, creation != current?.creationDate { return false }
        return true
    }

    private func remember(_ identity: String, for bookmark: Data) {
        defaults.set(["identity": identity, "bookmark": bookmark], forKey: Self.folderIdentityKey)
    }

    private func saveBookmark(_ data: Data, writable: Bool, identity: String) {
        remember(identity, for: data)
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
