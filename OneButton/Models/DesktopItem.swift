import AppKit
import Darwin

struct DesktopItem: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int? = nil
    var kind: String? = nil
    var lastUsedDate: Date? = nil
    var addedDate: Date? = nil
    var modifiedDate: Date? = nil
    var createdDate: Date? = nil
    var tags: [String] = []
    var applicationName: String? = nil
    var fileIdentity: FileIdentity? = nil

    var id: URL { url }

    var selectionKey: FileSelectionKey? {
        fileIdentity.map { FileSelectionKey(url: url, identity: $0) }
    }

    func isChild(of folder: URL) -> Bool {
        url.isFileURL && !["", "/", ".", ".."].contains(url.lastPathComponent)
            && url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
    }

    static func contents(of folder: URL, for sort: DesktopSort = .name) throws -> [DesktopItem] {
        var keys: Set<URLResourceKey> = [.localizedNameKey, .isDirectoryKey, .isPackageKey]
        switch sort {
        case .name, .application, .lastUsed: break
        case .size: keys.formUnion([.isRegularFileKey, .fileSizeKey])
        case .kind: keys.insert(.localizedTypeDescriptionKey)
        case .added: keys.insert(.addedToDirectoryDateKey)
        case .modified: keys.insert(.contentModificationDateKey)
        case .created: keys.insert(.creationDateKey)
        case .tags: keys.insert(.tagNamesKey)
        }
        return try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ).map { url in
            // A disappearing item must not prevent the other files from being listed.
            let values = try? url.resourceValues(forKeys: keys)
            var item = DesktopItem(
                url: url,
                name: values?.localizedName ?? url.lastPathComponent,
                isDirectory: values?.isDirectory == true && values?.isPackage != true,
                size: values?.isRegularFile == true ? values?.fileSize : nil,
                kind: values?.localizedTypeDescription,
                addedDate: values?.addedToDirectoryDate,
                modifiedDate: values?.contentModificationDate,
                createdDate: values?.creationDate,
                tags: values?.tagNames ?? [],
                fileIdentity: FileIdentity(url)
            )
            if sort == .application {
                item.applicationName = NSWorkspace.shared.urlForApplication(toOpen: url).map {
                    FileManager.default.displayName(atPath: $0.path)
                }
            } else if sort == .lastUsed {
                item.lastUsedDate = NSMetadataItem(url: url)?.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
            }
            return item
        }
    }
}

struct FileSelectionKey: Hashable, Sendable {
    let url: URL
    let identity: FileIdentity
}

struct FileIdentity: Hashable, Sendable {
    private let volume: dev_t
    private let inode: ino_t

    init?(_ url: URL, followingSymlinks: Bool = false) {
        var info = stat()
        // Selected items refer to the entry; a connected folder refers to its contents.
        let result = followingSymlinks ? stat(url.path, &info) : lstat(url.path, &info)
        guard result == 0 else { return nil }
        volume = info.st_dev
        inode = info.st_ino
    }
}

typealias DesktopSnapshot = (url: URL, items: [DesktopItem])
