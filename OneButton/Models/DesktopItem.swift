import AppKit

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

    var id: URL { url }

    static func contents(of folder: URL) throws -> [DesktopItem] {
        let keys: Set<URLResourceKey> = [
            .localizedNameKey, .isDirectoryKey, .isPackageKey, .isRegularFileKey,
            .fileSizeKey, .localizedTypeDescriptionKey, .addedToDirectoryDateKey,
            .contentModificationDateKey, .creationDateKey, .tagNamesKey
        ]
        let items = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ).map { url in
            // A disappearing item must not prevent the other files from being listed.
            let values = try? url.resourceValues(forKeys: keys)
            let applicationName = NSWorkspace.shared.urlForApplication(toOpen: url).map {
                FileManager.default.displayName(atPath: $0.path)
            }
            return DesktopItem(
                url: url,
                name: values?.localizedName ?? url.lastPathComponent,
                isDirectory: values?.isDirectory == true && values?.isPackage != true,
                size: values?.isRegularFile == true ? values?.fileSize : nil,
                kind: values?.localizedTypeDescription,
                lastUsedDate: NSMetadataItem(url: url)?.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                addedDate: values?.addedToDirectoryDate,
                modifiedDate: values?.contentModificationDate,
                createdDate: values?.creationDate,
                tags: values?.tagNames ?? [],
                applicationName: applicationName
            )
        }
        return DesktopSort.name.sorted(items, direction: .ascending)
    }
}

typealias DesktopSnapshot = (url: URL, items: [DesktopItem])
