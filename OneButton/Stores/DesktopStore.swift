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
    @Published private(set) var sortCriterion: DesktopSort
    @Published var sortDirection: DesktopSortDirection {
        didSet {
            defaults.set(sortDirection.rawValue, forKey: "desktopSortDirection")
            sortItems()
        }
    }

    private let defaults: UserDefaults
    private let access: DesktopAccess
    private let loadFolder: (DesktopSort) async throws -> DesktopSnapshot?
    private var folderIdentity: String?
    private var generation = 0
    private var operationError: String?

    init(
        defaults: UserDefaults = .standard,
        loadFolder: ((DesktopSort) async throws -> DesktopSnapshot?)? = nil
    ) {
        let access = DesktopAccess(defaults: defaults)
        self.defaults = defaults
        self.sortCriterion = DesktopSort(rawValue: defaults.string(forKey: "desktopSort") ?? "") ?? .name
        self.sortDirection = DesktopSortDirection(rawValue: defaults.string(forKey: "desktopSortDirection") ?? "") ?? .ascending
        self.access = access
        self.hasConnection = access.hasBookmark
        self.loadFolder = loadFolder ?? { try await access.loadFolder(for: $0) }
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
            let snapshot = try await loadFolder(sortCriterion)
            guard request == generation else { return }
            apply(snapshot)
            errorMessage = operationError
        } catch {
            guard request == generation else { return }
            folderURL = nil
            folderIdentity = nil
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
        let requestedSort = sortCriterion
        do {
            if let snapshot = try await access.chooseFolder(for: requestedSort) {
                apply(snapshot)
                operationError = nil
                errorMessage = nil
            }
        } catch {
            errorMessage = String(localized: "Could not connect the folder.\n\(error.localizedDescription)")
        }
        isChoosingFolder = false
        if sortCriterion != requestedSort && sortCriterion != .name && hasConnection { await refresh() }
    }

    private func apply(_ snapshot: DesktopSnapshot?) {
        folderURL = snapshot?.url
        // A real snapshot carries the identity checked during authorized enumeration.
        folderIdentity = access.connectedFolderIdentity ?? folderURL.flatMap(DesktopAccess.folderIdentity(at:))
        items = sortCriterion.sorted(snapshot?.items ?? [], direction: sortDirection)
        hasConnection = snapshot != nil || access.hasBookmark
    }

    func setSortCriterion(_ criterion: DesktopSort) async {
        guard sortCriterion != criterion else { return }
        sortCriterion = criterion
        defaults.set(criterion.rawValue, forKey: "desktopSort")
        if criterion == .name {
            sortItems()
        } else if !isChoosingFolder && (hasConnection || isLoading) {
            await refresh()
        }
    }

    func open(_ item: DesktopItem) async -> Bool {
        guard !isChoosingFolder, !isTrashing, openingURL == nil else { return false }
        guard let folderURL, let key = item.selectionKey, items.contains(where: { $0.selectionKey == key }) else {
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
        guard let folderURL, let folderIdentity, folderIdentity == DesktopAccess.folderIdentity(at: folderURL),
              containsSelection(selection, in: folderURL) else {
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
        var current = Set(items.compactMap(\.selectionKey))
        return selection.allSatisfy { item in
            guard item.isChild(of: folder), let key = item.selectionKey else { return false }
            return current.remove(key) != nil
        }
    }
}
