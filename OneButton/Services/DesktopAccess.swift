import AppKit

@MainActor
final class DesktopAccess {
    private static let bookmarkKey = "desktopBookmark"
    private let defaults: UserDefaults
    private var activeURL: URL?

    var hasBookmark: Bool { defaults.data(forKey: Self.bookmarkKey) != nil }

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
        panel.title = "바탕화면 연결"
        panel.message = "바탕화면 폴더를 선택해 주세요. 파일 목록을 표시하고 선택한 파일을 엽니다."
        panel.prompt = "연결"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

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
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: Self.bookmarkKey)
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = url
        connected = true
        return (url, items)
    }

    func open(_ item: DesktopItem, in folder: URL) async throws {
        let result: Bool? = try await withFolderAccess { current in
            guard current.standardizedFileURL == folder.standardizedFileURL,
                  item.url.isFileURL,
                  item.url.deletingLastPathComponent().standardizedFileURL == current.standardizedFileURL else {
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
                let updated = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                defaults.set(updated, forKey: Self.bookmarkKey)
            }
            activeURL = url
            return url
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
    }

    enum AccessError: LocalizedError {
        case invalidFolder, permissionDenied, changedFolder, openFailed

        var errorDescription: String? {
            switch self {
            case .invalidFolder: return "바탕화면 폴더를 선택해 주세요."
            case .permissionDenied: return "폴더에 접근할 수 없습니다. 바탕화면을 다시 연결해 주세요."
            case .changedFolder: return "폴더 연결이 변경되었습니다. 목록을 새로고침해 주세요."
            case .openFailed: return "연결된 앱에서 파일을 열지 못했습니다."
            }
        }
    }
}
