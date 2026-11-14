import AppKit

/// One Explorer tab: navigation row, command bar, navigation pane, file view and status bar.
final class ExplorerViewController: NSViewController {
    let model: BrowserModel
    weak var windowController: ExplorerWindowController?

    // Navigation row
    let backButton = NSButton()
    let forwardButton = NSButton()
    let upButton = NSButton()
    let refreshButton = NSButton()
    let addressBar = AddressBar()
    let searchField = NSSearchField()

    private(set) var commandBar: CommandBar!
    private(set) var statusBar: StatusBar!
    let sidebar = SidebarViewController()
    let splitVC = NSSplitViewController()
    let contentContainer = NSView()
    let emptyLabel = NSTextField(labelWithString: "")

    let previewPane = PreviewPaneViewController()
    private var previewItem: NSSplitViewItem!
    let detailsVC = DetailsViewController()
    let iconsVC = IconsViewController()
    private(set) var current: FileView!
    private(set) var viewMode: ViewMode = Prefs.viewMode
    private var pendingChange: BrowserModel.Change?
    private var showingSearchProgress = false

    init(url: URL) {
        model = BrowserModel(folder: url)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Layout

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 680))
        commandBar = CommandBar(target: self)
        statusBar = StatusBar(target: self)

        let navRow = makeNavigationRow()
        let content = makeSplit()
        let stack = NSStackView(views: [navRow, separator(), commandBar, separator(), content, separator(), statusBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fill
        root.addSubview(stack)
        stack.pinEdges(to: root)
        for v in stack.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        content.setContentHuggingPriority(.init(1), for: .vertical)
        view = root
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func navButton(_ button: NSButton, _ symbol: String, _ action: Selector, _ tip: String) -> NSButton {
        button.bezelStyle = .accessoryBarAction
        button.showsBorderOnlyWhileMouseInside = true
        button.image = NSImage.symbol(symbol, size: 14, weight: .medium)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.toolTip = tip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }

    private func makeNavigationRow() -> NSView {
        let back = navButton(backButton, "arrow.left", #selector(goBack(_:)), "Back (⌘[ / ⌥←)")
        let forward = navButton(forwardButton, "arrow.right", #selector(goForward(_:)), "Forward (⌘] / ⌥→)")
        let up = navButton(upButton, "arrow.up", #selector(goUp(_:)), "Up to parent folder (⌘↑ / ⌥↑)")
        let refresh = navButton(refreshButton, "arrow.clockwise", #selector(refresh(_:)), "Refresh (⌘R / F5)")

        addressBar.translatesAutoresizingMaskIntoConstraints = false
        addressBar.onNavigate = { [weak self] url in self?.navigate(to: url) }
        addressBar.onSubmit = { [weak self] text in self?.submitAddress(text) }

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.controlSize = .large
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true

        let row = NSStackView(views: [back, forward, up, refresh, addressBar, searchField])
        row.orientation = .horizontal
        row.spacing = 4
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 10)
        row.setCustomSpacing(10, after: refresh)
        row.setCustomSpacing(10, after: addressBar)
        addressBar.setContentHuggingPriority(.init(1), for: .horizontal)
        return row
    }

    private func makeSplit() -> NSView {
        sidebar.onNavigate = { [weak self] url in self?.navigate(to: url) }
        sidebar.onOpenInNewTab = { [weak self] url in self?.windowController?.openNewTab(at: url) }
        sidebar.onOpenInTerminal = { url in TerminalLauncher.open(url) }
        sidebar.onConnectToServer = { [weak self] in self?.connectToServer(nil) }
        sidebar.dropOperation = { [weak self] urls, folder, info in
            self?.dragOperation(for: urls, into: folder, info: info) ?? []
        }
        sidebar.onDrop = { [weak self] urls, folder, info in
            guard let self else { return false }
            let op = self.dragOperation(for: urls, into: folder, info: info)
            guard !op.isEmpty else { return false }
            self.transfer(urls, into: folder, move: op == .move)
            return true
        }

        let contentVC = NSViewController()
        contentVC.view = contentContainer
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        let sideItem = NSSplitViewItem(viewController: sidebar)
        sideItem.minimumThickness = 190
        sideItem.maximumThickness = 420
        sideItem.canCollapse = true
        sideItem.holdingPriority = .init(260)
        let mainItem = NSSplitViewItem(viewController: contentVC)
        mainItem.minimumThickness = 300
        splitVC.splitView.isVertical = true
        splitVC.splitView.dividerStyle = .thin
        splitVC.splitView.autosaveName = "ViFinder.Split"
        previewItem = NSSplitViewItem(viewController: previewPane)
        previewItem.minimumThickness = 220
        previewItem.maximumThickness = 900
        previewItem.canCollapse = true
        previewItem.holdingPriority = .init(255)
        splitVC.addSplitViewItem(sideItem)
        splitVC.addSplitViewItem(mainItem)
        splitVC.addSplitViewItem(previewItem)
        sideItem.isCollapsed = !Prefs.showNavigationPane
        previewItem.isCollapsed = !Prefs.showPreviewPane
        addChild(splitVC)
        splitVC.view.translatesAutoresizingMaskIntoConstraints = false
        splitVC.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        return splitVC.view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        detailsVC.host = self
        iconsVC.host = self
        addChild(detailsVC)
        addChild(iconsVC)
        installFileView(for: viewMode)

        model.onFolderChanged = { [weak self] in self?.folderChanged() }
        model.onItemsChanged = { [weak self] change in self?.itemsChanged(change) }
        current.setSortIndicator(model.sortKey, ascending: model.ascending)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(preferencesChanged), name: .viPreferencesChanged, object: nil)
        nc.addObserver(self, selector: #selector(clipboardChanged), name: .viClipboardChanged, object: nil)
        nc.addObserver(self, selector: #selector(clipboardChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        model.start()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        updateWindowTitle()
        current.focus()
        // First launch: give the navigation pane a comfortable width (afterwards the split view remembers it).
        if UserDefaults.standard.object(forKey: "NSSplitView Subview Frames ViFinder.Split") == nil,
           let pane = splitVC.splitViewItems.first, !pane.isCollapsed {
            splitVC.splitView.setPosition(240, ofDividerAt: 0)
        }
    }

    // MARK: File views

    private func installFileView(for mode: ViewMode) {
        let target: FileView
        if mode == .details {
            target = detailsVC
        } else {
            iconsVC.mode = mode
            target = iconsVC
        }
        if target !== current {
            current?.view.removeFromSuperview()
            contentContainer.addSubview(target.view, positioned: .below, relativeTo: nil)
            target.view.pinEdges(to: contentContainer)
            if emptyLabel.superview == nil {
                contentContainer.addSubview(emptyLabel)
                NSLayoutConstraint.activate([
                    emptyLabel.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
                    emptyLabel.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 60),
                    emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: contentContainer.widthAnchor, constant: -40),
                ])
            }
            current = target
        }
        viewMode = mode
        statusBar.setMode(mode)
    }

    func setViewMode(_ mode: ViewMode) {
        let selection = Set(current.selectedItems.map(\.url))
        Prefs.viewMode = mode
        installFileView(for: mode)
        current.display(model.items, selecting: selection, scrollToTop: false)
        current.setSortIndicator(model.sortKey, ascending: model.ascending)
        current.focus()
        updateStatus()
    }

    // MARK: Model updates

    private func folderChanged() {
        addressBar.setURL(model.folder)
        searchField.stringValue = ""
        searchField.placeholderString = "Search \(model.folder.displayName)"
        sidebar.highlight(model.folder)
        backButton.isEnabled = model.canGoBack
        forwardButton.isEnabled = model.canGoForward
        upButton.isEnabled = model.canGoUp
        emptyLabel.isHidden = true
        updateWindowTitle()
        updateCommandStates()
        updatePreview()
    }

    var isPreviewVisible: Bool { !(previewItem?.isCollapsed ?? true) }

    func updatePreview() {
        guard isPreviewVisible else { return }
        previewPane.show(current?.selectedItems ?? [])
    }

    private func itemsChanged(_ change: BrowserModel.Change) {
        if current.isRenaming {
            let previous = pendingChange
            pendingChange = BrowserModel.Change(
                isNewFolder: change.isNewFolder || (previous?.isNewFolder ?? false),
                select: change.select.union(previous?.select ?? []),
                rename: change.rename ?? previous?.rename)
            return
        }
        let keep: Set<URL> = change.isNewFolder ? [] : Set(current.selectedItems.map(\.url))
        current.setSearchRoot(model.isSearchMode ? model.folder : nil)
        current.display(model.items, selecting: keep.union(change.select), scrollToTop: change.isNewFolder)
        updateSearchProgress()
        updateEmptyState()
        updateStatus()
        updateCommandStates()
        if let rename = change.rename {
            DispatchQueue.main.async { [weak self] in self?.current.beginRename(rename) }
        }
    }

    func applyPendingChange() {
        guard let change = pendingChange else { return }
        pendingChange = nil
        itemsChanged(change)
    }

    private func updateEmptyState() {
        guard model.items.isEmpty else {
            emptyLabel.isHidden = true
            return
        }
        if let error = model.loadError {
            emptyLabel.stringValue = error
        } else if model.isSearchMode {
            emptyLabel.stringValue = model.isSearching ? "Searching…" : "No items match your search."
        } else {
            emptyLabel.stringValue = "This folder is empty."
        }
        emptyLabel.isHidden = false
    }

    private func updateSearchProgress() {
        let searching = model.isSearchMode && model.isSearching
        if searching {
            statusBar.setProgress("Searching sub-folders…")
            showingSearchProgress = true
        } else if showingSearchProgress {
            statusBar.setProgress(nil)
            showingSearchProgress = false
        }
    }

    func updateStatus() {
        var text = Formatters.itemCount(model.items.count)
        if model.isSearchMode && !model.isSearching && model.items.count >= BrowserModel.searchLimit {
            text += " (showing the first \(BrowserModel.searchLimit))"
        }
        let selected = current.selectedItems
        if !selected.isEmpty {
            text += "     " + (selected.count == 1 ? "1 item selected" : "\(selected.count) items selected")
            let files = selected.filter { !$0.isFolder }
            if !files.isEmpty {
                text += "  " + Formatters.size(files.reduce(Int64(0)) { $0 + ($1.size ?? 0) })
            }
        }
        statusBar.label.stringValue = text
    }

    func updateCommandStates() {
        let canWrite = FileManager.default.isWritableFile(atPath: model.folder.path)
        commandBar.update(hasSelection: !(current?.selectedItems.isEmpty ?? true),
                          canPaste: FileClipboard.shared.hasFiles, canWrite: canWrite)
    }

    func updateWindowTitle() {
        windowController?.tabDidUpdate(self)
    }

    @objc private func preferencesChanged() {
        model.apply()
        sidebar.refreshTree()
        let wantsPane = Prefs.showNavigationPane
        if let item = splitVC.splitViewItems.first, item.isCollapsed == wantsPane {
            item.animator().isCollapsed = !wantsPane
        }
        let wantsPreview = Prefs.showPreviewPane
        if previewItem.isCollapsed == wantsPreview {
            previewItem.animator().isCollapsed = !wantsPreview
            if wantsPreview, previewPane.view.frame.width < 260 {
                splitVC.splitView.setPosition(splitVC.splitView.bounds.width - 340, ofDividerAt: 1)
            }
            updatePreview()
        }
        current.refreshAppearance()
    }

    @objc private func clipboardChanged() {
        current.refreshAppearance()
        updateCommandStates()
    }

    // MARK: Navigation helpers

    func navigate(to url: URL) {
        model.navigate(to: url)
        current.focus()
    }

    private func submitAddress(_ text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let lower = input.lowercased()
        // Windows trick: type "cmd" in the address bar to open a terminal here.
        if ["cmd", "terminal", "powershell", "pwsh", "wt", "bash", "zsh", "sh"].contains(lower) {
            TerminalLauncher.open(model.folder)
            return
        }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://"), let web = URL(string: input) {
            NSWorkspace.shared.open(web)
            return
        }
        var path = (input as NSString).expandingTildeInPath
        if lower.hasPrefix("file://"), let fileURL = URL(string: input) { path = fileURL.path }
        if !path.hasPrefix("/") { path = model.folder.appendingPathComponent(path).path }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            if isDir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: path) {
                navigate(to: url)
            } else {
                NSWorkspace.shared.open(url)
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "ViFinder can't find '\(input)'."
            alert.informativeText = "Check the spelling and try again."
            alert.alertStyle = .warning
            alert.beginSheetModal(for: view.window!)
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        model.filterText = sender.stringValue
    }

    var selectedItems: [FileItem] { current.selectedItems }
    var selectedURLs: [URL] { current.selectedItems.map(\.url) }
}
