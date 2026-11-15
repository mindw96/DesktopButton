import AppKit
import Combine

@MainActor
final class DesktopStore: ObservableObject {
    @Published private(set) var items: [DesktopItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isChoosingFolder = false
    @Published private(set) var folderURL: URL?
    @Published private(set) var hasConnection: Bool
    @Published private(set) var errorMessage: String?
    @Published private(set) var isTrashing = false
    @Published private(set) var openingURL: URL?
    @Published var sortCriterion: DesktopSort {
        didSet {
            defaults.set(sortCriterion.rawValue, forKey: "desktopSort")
            sortItems()
        }
    }
    @Published var sortDirection: DesktopSortDirection {
        didSet {
            defaults.set(sortDirection.rawValue, forKey: "desktopSortDirection")
            sortItems()
        }
    }

    private let defaults: UserDefaults
    private let access: DesktopAccess
    private let loadFolder: () async throws -> DesktopSnapshot?
    private var generation = 0
    private var operationError: String?

    init(
        defaults: UserDefaults = .standard,
        loadFolder: (() async throws -> DesktopSnapshot?)? = nil
    ) {
        let access = DesktopAccess(defaults: defaults)
        self.defaults = defaults
        self.sortCriterion = DesktopSort(rawValue: defaults.string(forKey: "desktopSort") ?? "") ?? .name
        self.sortDirection = DesktopSortDirection(rawValue: defaults.string(forKey: "desktopSortDirection") ?? "") ?? .ascending
        self.access = access
        self.hasConnection = access.hasBookmark
        self.loadFolder = loadFolder ?? { try await access.loadFolder() }
    }

    func refresh() async {
        guard !isChoosingFolder else { return }
        generation += 1
        let request = generation
        isLoading = true
        defer {
            if request == generation { isLoading = false }
        }
        do {
            let snapshot = try await loadFolder()
            guard request == generation else { return }
            folderURL = snapshot?.url
            items = sortCriterion.sorted(snapshot?.items ?? [], direction: sortDirection)
            hasConnection = snapshot != nil || access.hasBookmark
            errorMessage = operationError
        } catch {
            guard request == generation else { return }
            folderURL = nil
            items = []
            hasConnection = access.hasBookmark || hasConnection
            let loadError = String(localized: "Could not load the file list.\n\(error.localizedDescription)")
            errorMessage = [operationError, loadError].compactMap { $0 }.joined(separator: "\n")
        }
    }

    func chooseFolder() async {
        guard !isChoosingFolder, !isTrashing, openingURL == nil else { return }
        generation += 1
        isLoading = false
        isChoosingFolder = true
        defer { isChoosingFolder = false }
        do {
            guard let snapshot = try await access.chooseFolder() else { return }
            folderURL = snapshot.url
            items = sortCriterion.sorted(snapshot.items, direction: sortDirection)
            hasConnection = true
            operationError = nil
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Could not connect the folder.\n\(error.localizedDescription)")
        }
    }

    func open(_ item: DesktopItem) async -> Bool {
        guard !isChoosingFolder, !isTrashing, openingURL == nil else { return false }
        guard let folderURL, items.contains(item) else {
            operationError = DesktopAccess.AccessError.changedFolder.localizedDescription
            errorMessage = operationError
            return false
        }
        openingURL = item.url
        defer { openingURL = nil }
        do {
            try await access.open(item, in: folderURL)
            operationError = nil
            errorMessage = nil
            return true
        } catch {
            let message = String(localized: "Could not open “\(item.name)”.\n\(error.localizedDescription)")
            operationError = message
            errorMessage = message
            return false
        }
    }

    func dismissError() {
        operationError = nil
        errorMessage = nil
    }

    private func sortItems() {
        items = sortCriterion.sorted(items, direction: sortDirection)
    }

    func moveToTrash(_ selection: [DesktopItem]) async {
        guard !selection.isEmpty, !isChoosingFolder, !isTrashing, openingURL == nil else { return }
        guard let folderURL, containsSelection(selection, in: folderURL) else {
            operationError = DesktopAccess.AccessError.changedItem.localizedDescription
            errorMessage = operationError
            return
        }
        isTrashing = true
        defer { isTrashing = false }
        do {
            try await access.moveToTrash(selection, in: folderURL)
            operationError = nil
        } catch {
            operationError = error.localizedDescription
        }
        await refresh()
    }

    func dragURLs(for selection: [DesktopItem]) -> [URL] {
        guard !selection.isEmpty, !isChoosingFolder, !isTrashing, openingURL == nil else { return [] }
        guard let folderURL, containsSelection(selection, in: folderURL) else {
            errorMessage = DesktopAccess.AccessError.changedFolder.localizedDescription
            return []
        }
        for item in selection {
            guard let identity = item.fileIdentity, identity == FileIdentity(item.url),
                  FileManager.default.isReadableFile(atPath: item.url.path) else {
                errorMessage = String(localized: "Could not share “\(item.name)”. Refresh or reconnect the folder.")
                return []
            }
        }
        // The connected folder's security scope stays active while this store is retained.
        return selection.map(\.url)
    }

    private func containsSelection(_ selection: [DesktopItem], in folder: URL) -> Bool {
        let current = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return Set(selection.map(\.id)).count == selection.count
            && selection.allSatisfy { $0.isChild(of: folder) && current[$0.id] == $0 }
    }
}
