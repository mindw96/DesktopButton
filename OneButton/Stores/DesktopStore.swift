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
    private var openError: String?

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
            errorMessage = openError
        } catch {
            guard request == generation else { return }
            folderURL = nil
            items = []
            hasConnection = access.hasBookmark || hasConnection
            errorMessage = "파일 목록을 불러오지 못했습니다.\n\(error.localizedDescription)"
        }
    }

    func chooseFolder() async {
        guard !isChoosingFolder, openingURL == nil else { return }
        generation += 1
        isLoading = false
        isChoosingFolder = true
        defer { isChoosingFolder = false }
        do {
            guard let snapshot = try await access.chooseFolder() else { return }
            folderURL = snapshot.url
            items = sortCriterion.sorted(snapshot.items, direction: sortDirection)
            hasConnection = true
            openError = nil
            errorMessage = nil
        } catch {
            errorMessage = "폴더를 연결하지 못했습니다.\n\(error.localizedDescription)"
        }
    }

    func open(_ item: DesktopItem) async -> Bool {
        guard !isChoosingFolder, openingURL == nil else { return false }
        guard let folderURL, items.contains(item) else {
            openError = DesktopAccess.AccessError.changedFolder.localizedDescription
            errorMessage = openError
            return false
        }
        openingURL = item.url
        defer { openingURL = nil }
        do {
            try await access.open(item, in: folderURL)
            openError = nil
            errorMessage = nil
            return true
        } catch {
            let message = "‘\(item.name)’ 파일을 열지 못했습니다.\n\(error.localizedDescription)"
            openError = message
            errorMessage = message
            return false
        }
    }

    func dismissError() {
        openError = nil
        errorMessage = nil
    }

    private func sortItems() {
        items = sortCriterion.sorted(items, direction: sortDirection)
    }

    func dragProvider(for item: DesktopItem) -> NSItemProvider {
        guard !isChoosingFolder, openingURL == nil,
              let folderURL, items.contains(item), item.url.isFileURL,
              item.url.deletingLastPathComponent().standardizedFileURL == folderURL.standardizedFileURL else {
            errorMessage = DesktopAccess.AccessError.changedFolder.localizedDescription
            return NSItemProvider()
        }
        guard FileManager.default.isReadableFile(atPath: item.url.path) else {
            errorMessage = "‘\(item.name)’ 파일을 전달할 수 없습니다. 폴더를 새로고침하거나 다시 연결해 주세요."
            return NSItemProvider()
        }
        // The connected folder's security scope stays active while this store is retained.
        let provider = NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
        provider.suggestedName = item.url.lastPathComponent
        return provider
    }
}
