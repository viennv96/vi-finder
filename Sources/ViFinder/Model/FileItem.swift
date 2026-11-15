import Foundation

/// Immutable snapshot of one entry inside a folder.
final class FileItem {
    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey, .isAliasFileKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
        .localizedTypeDescriptionKey,
        .tagNamesKey,
    ]

    let url: URL
    let name: String
    /// A folder the user can navigate into (includes symlinks pointing to folders, excludes packages like .app).
    let isFolder: Bool
    let isPackage: Bool
    let isHidden: Bool
    let isSymlink: Bool
    let size: Int64?
    let modified: Date?
    let created: Date?
    /// When the item was put in its current folder (Finder's "Date Added").
    let added: Date?
    let kind: String
    /// Finder tags ("Red", "Work"…).
    let tags: [String]

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        let values = try? url.resourceValues(forKeys: Set(FileItem.resourceKeys))
        let symlink = values?.isSymbolicLink ?? false
        var directory = values?.isDirectory ?? false
        var package = values?.isPackage ?? false
        if symlink {
            let target = url.resolvingSymlinksInPath()
            let tv = try? target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            directory = tv?.isDirectory ?? false
            package = tv?.isPackage ?? false
        }
        self.isSymlink = symlink
        self.isPackage = package
        self.isFolder = directory && !package
        self.isHidden = (values?.isHidden ?? false) || name.hasPrefix(".")
        self.size = directory ? nil : Int64(values?.fileSize ?? 0)
        self.modified = values?.contentModificationDate
        self.created = values?.creationDate
        self.added = values?.addedToDirectoryDate
        self.tags = values?.tagNames ?? []
        if self.isFolder {
            self.kind = symlink ? "Folder shortcut" : "File folder"
        } else {
            self.kind = values?.localizedTypeDescription ?? "File"
        }
    }

    var pathExtension: String { url.pathExtension }

    func displayName(showExtension: Bool) -> String {
        if showExtension || isFolder || pathExtension.isEmpty { return name }
        return (name as NSString).deletingPathExtension
    }
}

extension FileItem {
    /// Windows-like ordering: folders first, then the requested key, ties broken by name.
    static func sort(_ items: [FileItem], by key: SortKey, ascending: Bool) -> [FileItem] {
        items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let result: ComparisonResult
            switch key {
            case .name:
                result = a.name.localizedStandardCompare(b.name)
            case .dateModified:
                result = compare(a.modified ?? .distantPast, b.modified ?? .distantPast)
            case .dateCreated:
                result = compare(a.created ?? .distantPast, b.created ?? .distantPast)
            case .dateAdded:
                result = compare(a.added ?? .distantPast, b.added ?? .distantPast)
            case .type:
                let r = a.kind.localizedCaseInsensitiveCompare(b.kind)
                result = r == .orderedSame ? a.name.localizedStandardCompare(b.name) : r
            case .size:
                result = compare(a.size ?? -1, b.size ?? -1)
            }
            if result == .orderedSame {
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
