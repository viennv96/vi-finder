import Foundation

/// Navigation + listing state of one Explorer tab.
final class BrowserModel {
    struct Change {
        /// True when a different folder was opened (UI should scroll to top).
        let isNewFolder: Bool
        /// Items the UI should select after applying this change.
        let select: Set<URL>
        /// Item that should enter rename mode right away (e.g. "New folder").
        let rename: URL?
    }

    private(set) var folder: URL
    private(set) var items: [FileItem] = []
    private(set) var allItems: [FileItem] = []
    private(set) var loadError: String?
    private(set) var isLoading = false

    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []

    var sortKey: SortKey = Prefs.sortKey
    var ascending: Bool = Prefs.sortAscending
    var filterText = "" {
        didSet { if filterText != oldValue && !suppressApply { apply(isNewFolder: false) } }
    }

    /// Called right after `folder` changes (before the listing is loaded).
    var onFolderChanged: (() -> Void)?
    /// Called whenever `items` changes.
    var onItemsChanged: ((Change) -> Void)?

    private let monitor = DirectoryMonitor()
    private var generation = 0
    private var pendingSelect: Set<URL> = []
    private var pendingRename: URL?
    private var pendingNewFolder = false
    private var debounce: DispatchWorkItem?
    private var suppressApply = false

    init(folder: URL) {
        self.folder = folder.standardizedFileURL
        monitor.onChange = { [weak self] in self?.scheduleReload() }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { !folder.isRoot }

    // MARK: Navigation

    func navigate(to url: URL, recordHistory: Bool = true, select: Set<URL> = []) {
        let target = url.standardizedFileURL
        if recordHistory && !target.isSameFile(as: folder) {
            backStack.append(folder)
            forwardStack.removeAll()
        }
        folder = target
        suppressApply = true
        filterText = ""
        suppressApply = false
        pendingSelect = select
        pendingRename = nil
        pendingNewFolder = true
        items = []
        allItems = []
        loadError = nil
        monitor.start(target)
        onFolderChanged?()
        load()
    }

    /// Start listing the initial folder.
    func start() { navigate(to: folder, recordHistory: false) }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(folder)
        let from = folder
        navigate(to: previous, recordHistory: false, select: [from])
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(folder)
        navigate(to: next, recordHistory: false)
    }

    func goUp() {
        guard canGoUp else { return }
        let from = folder
        navigate(to: folder.deletingLastPathComponent(), select: [from])
    }

    // MARK: Loading

    /// Reload the current folder, optionally selecting / renaming items once loaded.
    func reload(select: Set<URL> = [], rename: URL? = nil) {
        pendingSelect.formUnion(select.map { $0.standardizedFileURL })
        if let rename { pendingRename = rename.standardizedFileURL }
        load()
    }

    private func scheduleReload() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.load() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func load() {
        generation += 1
        let gen = generation
        let folder = self.folder
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var loaded: [FileItem] = []
            var errorText: String?
            do {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: FileItem.resourceKeys, options: [])
                loaded = urls.map { FileItem(url: $0.standardizedFileURL) }
            } catch {
                errorText = BrowserModel.describe(error)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.generation else { return }
                self.isLoading = false
                self.allItems = loaded
                self.loadError = errorText
                self.apply(isNewFolder: self.pendingNewFolder)
            }
        }
    }

    /// Re-filter and re-sort without touching the disk.
    func apply(isNewFolder: Bool = false) {
        let showHidden = Prefs.showHidden
        var visible = allItems.filter { showHidden || !$0.isHidden }
        let query = filterText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            visible = visible.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        items = FileItem.sort(visible, by: sortKey, ascending: ascending)
        let change = Change(isNewFolder: isNewFolder, select: pendingSelect, rename: pendingRename)
        pendingSelect = []
        pendingRename = nil
        pendingNewFolder = false
        onItemsChanged?(change)
    }

    func setSort(_ key: SortKey, ascending: Bool) {
        sortKey = key
        self.ascending = ascending
        Prefs.sortKey = key
        Prefs.sortAscending = ascending
        apply()
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoPermissionError {
            return "You don't currently have permission to access this folder."
        }
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadNoSuchFileError {
            return "This location is not available. It may have been moved or deleted."
        }
        return ns.localizedDescription
    }
}
