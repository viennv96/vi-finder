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
        didSet { if filterText != oldValue && !suppressApply { scheduleSearch() } }
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

    // Search (like Explorer: current folder + all sub-folders)
    static let searchLimit = 10_000
    private final class SearchToken { var cancelled = false }
    private var searchToken: SearchToken?
    private var searchDebounce: DispatchWorkItem?
    private var searchResults: [FileItem] = []
    private(set) var isSearching = false
    var searchQuery: String { filterText.trimmingCharacters(in: .whitespaces) }
    var isSearchMode: Bool { !searchQuery.isEmpty }

    init(folder: URL) {
        self.folder = folder.standardizedFileURL
        monitor.onChange = { [weak self] in self?.scheduleReload() }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { !folder.isRoot && !isTagView }
    /// Virtual "all files with this tag" view (Spotlight results).
    var isTagView: Bool { folder.isTagLocation }
    private var tagQuery: NSMetadataQuery?
    private var tagObserver: NSObjectProtocol?

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
        cancelSearch()
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
        if isSearchMode && !isTagView { startSearch() } else { load() }
    }

    // MARK: Search

    private func cancelSearch() {
        searchDebounce?.cancel()
        searchToken?.cancelled = true
        searchToken = nil
        searchResults = []
        isSearching = false
    }

    private func scheduleSearch() {
        searchDebounce?.cancel()
        guard isSearchMode, !isTagView else {
            cancelSearch()
            apply()
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.startSearch() }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Walks the folder tree in the background; results stream in every ~0.3 s.
    /// Matching ignores case and Vietnamese diacritics ("tai lieu" finds "Tài liệu").
    private func startSearch() {
        searchToken?.cancelled = true
        let token = SearchToken()
        searchToken = token
        let root = folder
        let query = searchQuery
        let showHidden = Prefs.showHidden
        searchResults = []
        isSearching = true
        apply()
        DispatchQueue.global(qos: .userInitiated).async {
            var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
            if !showHidden { options.insert(.skipsHiddenFiles) }
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: FileItem.resourceKeys,
                                                            options: options) { _, _ in true }
            var batch: [FileItem] = []
            var found = 0
            var lastFlush = Date()
            func flush(final: Bool) {
                let chunk = batch
                batch = []
                DispatchQueue.main.async { [weak self] in
                    guard let self, !token.cancelled else { return }
                    self.searchResults += chunk
                    if final { self.isSearching = false }
                    self.apply()
                }
            }
            while let url = enumerator?.nextObject() as? URL {
                if token.cancelled { return }
                if url.lastPathComponent.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    batch.append(FileItem(url: url.standardizedFileURL))
                    found += 1
                    if found >= BrowserModel.searchLimit { break }
                }
                if !batch.isEmpty && Date().timeIntervalSince(lastFlush) > 0.3 {
                    flush(final: false)
                    lastFlush = Date()
                }
            }
            flush(final: true)
        }
    }

    private func scheduleReload() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.load() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func load() {
        if let tag = folder.tagName {
            loadTag(tag)
            return
        }
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

    /// Asks Spotlight for every file carrying `tag` (like Finder's Tags sidebar items).
    private func loadTag(_ tag: String) {
        tagQuery?.stop()
        if let tagObserver { NotificationCenter.default.removeObserver(tagObserver) }
        generation += 1
        let gen = generation
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K == %@", "kMDItemUserTags", tag)
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        isLoading = true
        tagObserver = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] note in
            guard let query = note.object as? NSMetadataQuery else { return }
            query.disableUpdates()
            let paths = (0..<query.resultCount).compactMap {
                (query.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemPathKey) as? String
            }
            query.stop()
            DispatchQueue.global(qos: .userInitiated).async {
                let found = paths.filter { FileManager.default.fileExists(atPath: $0) }
                    .map { FileItem(url: URL(fileURLWithPath: $0).standardizedFileURL) }
                DispatchQueue.main.async {
                    guard let self, gen == self.generation else { return }
                    self.isLoading = false
                    self.allItems = found
                    self.loadError = nil
                    self.apply(isNewFolder: self.pendingNewFolder)
                }
            }
        }
        tagQuery = query
        query.start()
    }

    /// Re-filter and re-sort without touching the disk.
    func apply(isNewFolder: Bool = false) {
        let showHidden = Prefs.showHidden
        var visible = isSearchMode && !isTagView ? searchResults : allItems.filter { showHidden || !$0.isHidden }
        if isTagView && isSearchMode {
            visible = visible.filter { $0.name.range(of: searchQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        items = FileItem.sort(visible, by: sortKey, ascending: ascending)
        let change = Change(isNewFolder: isNewFolder, select: pendingSelect, rename: pendingRename)
        // While a search is still streaming, keep pending selection until the final batch.
        if !isSearching {
            pendingSelect = []
            pendingRename = nil
        }
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
