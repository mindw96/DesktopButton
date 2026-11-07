import Foundation

struct DesktopItem: Identifiable, Equatable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool

    var id: URL { url }

    static func contents(of folder: URL) throws -> [DesktopItem] {
        let keys: Set<URLResourceKey> = [.localizedNameKey, .isDirectoryKey, .isPackageKey]
        return try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ).map { url in
            // A disappearing item must not prevent the other files from being listed.
            let values = try? url.resourceValues(forKeys: keys)
            return DesktopItem(
                url: url,
                name: values?.localizedName ?? url.lastPathComponent,
                isDirectory: values?.isDirectory == true && values?.isPackage != true
            )
        }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame
                ? $0.url.path < $1.url.path
                : order == .orderedAscending
        }
    }
}

typealias DesktopSnapshot = (url: URL, items: [DesktopItem])
