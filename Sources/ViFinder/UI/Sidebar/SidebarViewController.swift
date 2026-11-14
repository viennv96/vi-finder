import AppKit
import SystemConfiguration

/// A row in the navigation pane. Folder nodes lazily load their sub-folders (Windows-style tree).
final class SidebarNode {
    let title: String
    let url: URL?
    let symbol: String?
    let isGroup: Bool
    /// Pinned Quick access items are leaves (also avoids privacy prompts for Desktop/Documents at launch).
    let canExpand: Bool
    /// Custom icon (e.g. the OneDrive / Google Drive app icon) instead of an SF Symbol.
    var image: NSImage?
    /// Rows like "Network" run an action instead of navigating.
    var action: (() -> Void)?
    private(set) var loadedChildren: [SidebarNode]?
    var fixedChildren: [SidebarNode]?

    init(group title: String, children: [SidebarNode]) {
        self.title = title
        self.url = nil
        self.symbol = nil
        self.isGroup = true
        self.canExpand = true
        self.fixedChildren = children
    }

    init(title: String, url: URL, symbol: String? = nil, canExpand: Bool = true) {
        self.title = title
        self.url = url
        self.symbol = symbol
        self.isGroup = false
        self.canExpand = canExpand
    }

    init(title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.url = nil
        self.symbol = symbol
        self.isGroup = false
        self.canExpand = false
        self.action = action
    }

    var children: [SidebarNode] {
        if let fixedChildren { return fixedChildren }
        if let loadedChildren { return loadedChildren }
        loadedChildren = SidebarNode.subfolders(of: url)
        return loadedChildren ?? []
    }

    var isExpandable: Bool {
        if let fixedChildren { return !fixedChildren.isEmpty }
        guard canExpand, let url else { return false }
        if let loadedChildren { return !loadedChildren.isEmpty }
        return SidebarNode.hasSubfolder(url)
    }

    func invalidate() { loadedChildren = nil }

    private static func subfolders(of url: URL?) -> [SidebarNode] {
        guard let url else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey]
        let options: FileManager.DirectoryEnumerationOptions = Prefs.showHidden ? [] : [.skipsHiddenFiles]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: options) else { return [] }
        return urls.filter { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .map { SidebarNode(title: $0.displayName, url: $0.standardizedFileURL) }
    }

    private static func hasSubfolder(_ url: URL) -> Bool {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        if !Prefs.showHidden { options.insert(.skipsHiddenFiles) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                                                     options: options) else { return false }
        var checked = 0
        for case let child as URL in e {
            let v = try? child.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if (v?.isDirectory ?? false) && !(v?.isPackage ?? false) { return true }
            checked += 1
            if checked > 400 { return true } // big folder: assume it has sub-folders
        }
        return false
    }
}

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onNavigate: ((URL) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?
    var onOpenInTerminal: ((URL) -> Void)?
    var onConnectToServer: (() -> Void)?
    var onDrop: ((_ urls: [URL], _ folder: URL, _ info: NSDraggingInfo) -> Bool)?
    var dropOperation: ((_ urls: [URL], _ folder: URL, _ info: NSDraggingInfo) -> NSDragOperation)?

    private let outline = NSOutlineView()
    private var roots: [SidebarNode] = []
    private var suppressSelection = false

    override func loadView() {
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.floatsGroupRows = false
        outline.indentationPerLevel = 12
        outline.autoresizesOutlineColumn = false
        outline.dataSource = self
        outline.delegate = self
        outline.registerForDraggedTypes([.fileURL])
        outline.menu = NSMenu()
        outline.menu?.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        view = scroll

        reloadRoots()
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didMountNotification, object: nil)
        ws.addObserver(self, selector: #selector(volumesChanged), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func volumesChanged() { reloadRoots() }

    func reloadRoots() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        func dir(_ d: FileManager.SearchPathDirectory) -> URL {
            fm.urls(for: d, in: .userDomainMask).first ?? home
        }
        let quick: [SidebarNode] = [
            ("Home", home, "house"),
            ("Desktop", dir(.desktopDirectory), "menubar.dock.rectangle"),
            ("Downloads", dir(.downloadsDirectory), "arrow.down.circle"),
            ("Documents", dir(.documentDirectory), "doc.text"),
            ("Pictures", dir(.picturesDirectory), "photo"),
            ("Music", dir(.musicDirectory), "music.note"),
            ("Videos", dir(.moviesDirectory), "film"),
            ("Applications", URL(fileURLWithPath: "/Applications"), "square.grid.3x3"),
        ].map { SidebarNode(title: $0.0, url: $0.1.standardizedFileURL, symbol: $0.2, canExpand: false) }
        let volumeURLs = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeLocalizedNameKey],
                                              options: [.skipHiddenVolumes]) ?? [URL(fileURLWithPath: "/")]
        let drives = volumeURLs.map { url -> SidebarNode in
            let values = try? url.resourceValues(forKeys: [.volumeIsRemovableKey, .volumeIsLocalKey])
            let symbol: String
            if url.isRoot { symbol = "internaldrive" }
            else if values?.volumeIsLocal == false { symbol = "server.rack" }
            else if values?.volumeIsRemovable == true { symbol = "externaldrive" }
            else { symbol = "externaldrive.connected.to.line.below" }
            return SidebarNode(title: url.displayName, url: url.standardizedFileURL, symbol: symbol)
        }
        // "This PC" equivalent: the Mac itself, containing every drive.
        let computer = SidebarNode(title: SidebarViewController.computerName,
                                   url: URL(fileURLWithPath: "/Volumes"), symbol: "desktopcomputer")
        computer.fixedChildren = drives

        var locations: [SidebarNode] = [computer]
        locations += SidebarViewController.cloudStorageNodes()
        locations.append(SidebarNode(title: "Network", symbol: "network") { [weak self] in self?.onConnectToServer?() })

        var groups = [SidebarNode(group: "Quick access", children: quick)]
        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: iCloud.path) {
            groups.append(SidebarNode(group: "iCloud", children: [
                SidebarNode(title: "iCloud Drive", url: iCloud.standardizedFileURL, symbol: "icloud", canExpand: false),
            ]))
        }
        groups.append(SidebarNode(group: "Locations", children: locations))
        roots = groups
        computerNode = computer
        outline.reloadData()
        for root in roots { outline.expandItem(root) }
        if let computerNode { outline.expandItem(computerNode) }
    }

    private weak var computerNode: SidebarNode?

    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"
    }

    /// OneDrive, Google Drive, Dropbox, Box… (File Provider folders in ~/Library/CloudStorage).
    static func cloudStorageNodes() -> [SidebarNode] {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/CloudStorage")
        guard let folders = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles]) else { return [] }
        let providers: [(prefix: String, name: String, bundleID: String)] = [
            ("OneDrive", "OneDrive", "com.microsoft.OneDrive"),
            ("GoogleDrive", "Google Drive", "com.google.drivefs"),
            ("Dropbox", "Dropbox", "com.getdropbox.dropbox"),
            ("Box", "Box", "com.box.desktop"),
            ("pCloud", "pCloud Drive", "com.pcloud.pcloud.macos"),
        ]
        return folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let raw = url.lastPathComponent
                let provider = providers.first { raw.hasPrefix($0.prefix) }
                var title = raw
                if let provider {
                    let account = raw.dropFirst(provider.prefix.count).drop { $0 == "-" }
                    title = account.isEmpty ? provider.name : "\(provider.name) - \(account)"
                }
                let node = SidebarNode(title: title, url: url.standardizedFileURL, symbol: "cloud", canExpand: false)
                if let id = provider?.bundleID, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    node.image = NSWorkspace.shared.icon(forFile: app.path)
                }
                return node
            }
    }

    /// Reflects the current folder in the pane (only for top-level locations, like Windows).
    func highlight(_ url: URL) {
        suppressSelection = true
        defer { suppressSelection = false }
        for row in 0..<outline.numberOfRows {
            if let node = outline.item(atRow: row) as? SidebarNode, let nodeURL = node.url, nodeURL.isSameFile(as: url) {
                outline.selectRowIndexes([row], byExtendingSelection: false)
                return
            }
        }
        outline.deselectAll(nil)
    }

    /// Re-reads expanded folders (e.g. hidden items toggled).
    func refreshTree() {
        func walk(_ nodes: [SidebarNode]) {
            for n in nodes where n.fixedChildren == nil { n.invalidate() }
            for n in nodes { if let fixed = n.fixedChildren { walk(fixed) } }
        }
        walk(roots)
        outline.reloadData()
        for root in roots { outline.expandItem(root) }
    }

    // MARK: Data source

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? SidebarNode else { return roots.count }
        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? SidebarNode else { return roots[index] }
        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.isExpandable ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.isGroup ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !((item as? SidebarNode)?.isGroup ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        if node.isGroup {
            let id = NSUserInterfaceItemIdentifier("header")
            let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
                let c = NSTableCellView()
                c.identifier = id
                let t = NSTextField(labelWithString: "")
                t.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(t)
                c.textField = t
                NSLayoutConstraint.activate([
                    t.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    t.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = node.title
            return cell
        }
        let id = NSUserInterfaceItemIdentifier("location")
        let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let c = NSTableCellView()
            c.identifier = id
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyUpOrDown
            let t = NSTextField(labelWithString: "")
            t.translatesAutoresizingMaskIntoConstraints = false
            t.lineBreakMode = .byTruncatingTail
            c.addSubview(image)
            c.addSubview(t)
            c.imageView = image
            c.textField = t
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                t.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                t.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
                t.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            return c
        }()
        cell.textField?.stringValue = node.title
        if let image = node.image {
            cell.imageView?.image = image
            cell.imageView?.contentTintColor = nil
        } else if let symbol = node.symbol {
            cell.imageView?.image = NSImage.symbol(symbol, size: 14)
            cell.imageView?.contentTintColor = .controlAccentColor
        } else if let url = node.url {
            cell.imageView?.image = IconProvider.icon(for: url)
            cell.imageView?.contentTintColor = nil
        }
        cell.toolTip = node.url?.path
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, let node = outline.item(atRow: outline.selectedRow) as? SidebarNode else { return }
        if let action = node.action {
            action()
            return
        }
        if let url = node.url { onNavigate?(url) }
    }

    // MARK: Drop onto sidebar folders

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        guard let node = item as? SidebarNode, let url = node.url, index == NSOutlineViewDropOnItemIndex else { return [] }
        let urls = DragSupport.fileURLs(from: info)
        guard !urls.isEmpty else { return [] }
        return dropOperation?(urls, url, info) ?? []
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let node = item as? SidebarNode, let url = node.url else { return false }
        return onDrop?(DragSupport.fileURLs(from: info), url, info) ?? false
    }
}

// MARK: Context menu

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard outline.clickedRow >= 0, let node = outline.item(atRow: outline.clickedRow) as? SidebarNode,
              let url = node.url else { return }
        menu.addItem("Open", #selector(menuOpen(_:)), target: self, represented: url)
        menu.addItem("Open in new tab", #selector(menuOpenTab(_:)), target: self, symbol: "plus.square.on.square", represented: url)
        menu.addSeparator()
        menu.addItem("Open in Terminal", #selector(menuTerminal(_:)), target: self, symbol: "terminal", represented: url)
        menu.addItem("Show in Finder", #selector(menuReveal(_:)), target: self, symbol: "macwindow", represented: url)
        menu.addItem("Copy as path", #selector(menuCopyPath(_:)), target: self, symbol: "link", represented: url)
    }

    @objc private func menuOpen(_ sender: NSMenuItem) { (sender.representedObject as? URL).map { onNavigate?($0) } }
    @objc private func menuOpenTab(_ sender: NSMenuItem) { (sender.representedObject as? URL).map { onOpenInNewTab?($0) } }
    @objc private func menuTerminal(_ sender: NSMenuItem) { (sender.representedObject as? URL).map { onOpenInTerminal?($0) } }
    @objc private func menuReveal(_ sender: NSMenuItem) {
        (sender.representedObject as? URL).map { DefaultFileBrowser.revealInFinder([$0]) }
    }
    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        (sender.representedObject as? URL).map { FileClipboard.shared.writeText($0.path) }
    }
}
