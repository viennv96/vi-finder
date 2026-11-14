import AppKit
import Quartz

// MARK: - Context menus & command bar menus

extension ExplorerViewController {
    /// Right-click on one or more items.
    func itemMenu(for items: [FileItem]) -> NSMenu {
        let menu = NSMenu()
        let urls = items.map(\.url)
        let single = items.count == 1 ? items[0] : nil
        let allFolders = items.allSatisfy(\.isFolder)

        menu.addItem("Open", #selector(openSelection(_:)), target: self, symbol: "arrow.up.forward.app")
        if allFolders {
            menu.addItem("Open in new tab", #selector(openInNewTab(_:)), target: self, symbol: "plus.square.on.square", represented: urls)
            menu.addItem("Open in new window", #selector(openInNewWindow(_:)), target: self, symbol: "macwindow.badge.plus", represented: urls)
        }
        if !allFolders || items.contains(where: \.isPackage) {
            menu.addItem(openWithMenuItem(for: urls))
        }
        menu.addSeparator()

        let terminalTarget = (single?.isFolder ?? false) ? single!.url : model.folder
        addTerminalItems(to: menu, folder: terminalTarget)
        menu.addSeparator()

        menu.addItem("Cut", #selector(cut(_:)), target: self, key: "x", symbol: "scissors")
        menu.addItem("Copy", #selector(copy(_:)), target: self, key: "c", symbol: "doc.on.doc")
        if let folder = single, folder.isFolder {
            menu.addItem("Paste into folder", #selector(paste(_:)), target: self, symbol: "doc.on.clipboard", represented: folder.url)
        }
        menu.addItem("Copy as path", #selector(copyAsPath(_:)), target: self, key: "c", modifiers: [.command, .option],
                     symbol: "link", represented: urls)
        menu.addSeparator()

        menu.addItem("Rename", #selector(renameSelection(_:)), target: self, key: FunctionKey.f2, modifiers: [],
                     symbol: "character.cursor.ibeam").isEnabled = single != nil
        menu.addItem("Delete", #selector(moveToTrash(_:)), target: self, key: FunctionKey.backspace,
                     symbol: "trash", represented: urls)
        menu.addItem("Delete permanently", #selector(deletePermanently(_:)), target: self, key: FunctionKey.backspace,
                     modifiers: [.shift], symbol: "trash.slash", represented: urls)
        menu.addSeparator()

        menu.addItem("Compress to ZIP file", #selector(compressSelection(_:)), target: self, symbol: "doc.zipper", represented: urls)
        if let zip = single, zip.pathExtension.lowercased() == "zip" {
            menu.addItem("Extract All…", #selector(extractSelection(_:)), target: self, symbol: "arrow.up.bin", represented: [zip.url])
        }
        menu.addItem("Share", #selector(shareSelection(_:)), target: self, symbol: "square.and.arrow.up")
        menu.addItem("Show in Finder", #selector(revealInFinder(_:)), target: self, symbol: "macwindow", represented: urls)
        menu.addSeparator()
        menu.addItem("Properties", #selector(showProperties(_:)), target: self, key: "i", symbol: "info.circle", represented: urls)
        return menu
    }

    /// Right-click on empty space in the folder.
    func backgroundMenu() -> NSMenu {
        let menu = NSMenu()
        let view = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        view.image = NSImage.symbol("rectangle.grid.1x2", size: 13)
        view.submenu = viewMenu(includeToggles: false)
        menu.addItem(view)
        let sort = NSMenuItem(title: "Sort by", action: nil, keyEquivalent: "")
        sort.image = NSImage.symbol("arrow.up.arrow.down", size: 13)
        sort.submenu = sortMenu()
        menu.addItem(sort)
        menu.addItem("Refresh", #selector(refresh(_:)), target: self, key: "r", symbol: "arrow.clockwise")
        menu.addSeparator()
        menu.addItem("Paste", #selector(paste(_:)), target: self, key: "v", symbol: "doc.on.clipboard")
        menu.addSeparator()
        let new = NSMenuItem(title: "New", action: nil, keyEquivalent: "")
        new.image = NSImage.symbol("plus.circle", size: 13)
        new.submenu = newMenu()
        menu.addItem(new)
        menu.addSeparator()
        addTerminalItems(to: menu, folder: model.folder)
        menu.addItem("Copy as path", #selector(copyAsPath(_:)), target: self, symbol: "link", represented: [model.folder])
        menu.addItem("Show in Finder", #selector(revealInFinder(_:)), target: self, symbol: "macwindow", represented: [model.folder])
        menu.addSeparator()
        menu.addItem("Properties", #selector(showProperties(_:)), target: self, symbol: "info.circle", represented: [model.folder])
        return menu
    }

    /// "Open in Terminal" + "Open in ▸" (other terminals / code editors) + default terminal chooser.
    func addTerminalItems(to menu: NSMenu, folder: URL) {
        let preferred = TerminalLauncher.preferred
        let main = menu.addItem("Open in \(preferred.name)", #selector(openInTerminal(_:)), target: self,
                                symbol: "terminal", represented: folder)
        main.keyEquivalent = "t"
        main.keyEquivalentModifierMask = [.command, .option]

        let others = TerminalLauncher.installedTerminals.filter { $0.bundleID != preferred.bundleID } + TerminalLauncher.installedEditors
        guard !others.isEmpty else { return }
        let sub = NSMenu()
        for app in others {
            let item = sub.addItem(app.name, #selector(openInSpecificApp(_:)), target: self,
                                   represented: AppTarget(app: app, urls: [folder]))
            item.image = app.icon
        }
        let terminals = TerminalLauncher.installedTerminals
        if terminals.count > 1 {
            sub.addSeparator()
            let header = NSMenuItem(title: "Default terminal", action: nil, keyEquivalent: "")
            header.isEnabled = false
            sub.addItem(header)
            for app in terminals {
                let item = sub.addItem(app.name, #selector(setDefaultTerminal(_:)), target: self, represented: app.bundleID)
                item.state = app.bundleID == preferred.bundleID ? .on : .off
                item.indentationLevel = 1
            }
        }
        let holder = NSMenuItem(title: "Open in", action: nil, keyEquivalent: "")
        holder.image = NSImage.symbol("chevron.left.forwardslash.chevron.right", size: 13)
        holder.submenu = sub
        menu.addItem(holder)
    }

    func openWithMenuItem(for urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: "Open with", action: nil, keyEquivalent: "")
        item.image = NSImage.symbol("arrow.up.right.square", size: 13)
        let sub = NSMenu()
        if let first = urls.first {
            let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: first)
            var apps = NSWorkspace.shared.urlsForApplications(toOpen: first)
            if let defaultApp { apps.removeAll { $0 == defaultApp }; apps.insert(defaultApp, at: 0) }
            var seen = Set<String>()
            for app in apps.prefix(25) where seen.insert(app.path).inserted {
                var name = FileManager.default.displayName(atPath: app.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                if app == defaultApp { name += " (default)" }
                let entry = sub.addItem(name, #selector(openWithApp(_:)), target: self,
                                        represented: AppTarget(appURL: app, urls: urls))
                let icon = NSWorkspace.shared.icon(forFile: app.path)
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
        }
        if !sub.items.isEmpty { sub.addSeparator() }
        sub.addItem("Choose another app…", #selector(openWithOther(_:)), target: self, represented: AppTarget(urls: urls))
        item.submenu = sub
        return item
    }

    func newMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem("Folder", #selector(newFolder(_:)), target: self, key: "n", modifiers: [.command, .shift], symbol: "folder.badge.plus")
        menu.addSeparator()
        menu.addItem("Text Document", #selector(newTextDocument(_:)), target: self, symbol: "doc.text")
        return menu
    }

    func sortMenu() -> NSMenu {
        let menu = NSMenu()
        for key in SortKey.allCases {
            let item = menu.addItem(key.title, #selector(sortFromMenu(_:)), target: self, represented: key.rawValue)
            item.state = model.sortKey == key ? .on : .off
        }
        menu.addSeparator()
        let asc = menu.addItem("Ascending", #selector(sortFromMenu(_:)), target: self, tag: 1)
        asc.state = model.ascending ? .on : .off
        let desc = menu.addItem("Descending", #selector(sortFromMenu(_:)), target: self, tag: 0)
        desc.state = model.ascending ? .off : .on
        return menu
    }

    func viewMenu(includeToggles: Bool) -> NSMenu {
        let menu = NSMenu()
        for (index, mode) in ViewMode.allCases.enumerated() {
            let item = menu.addItem(mode.title, #selector(setViewModeFromMenu(_:)), target: self,
                                    key: "\(index + 1)", symbol: mode.symbol, represented: mode.rawValue)
            item.state = viewMode == mode ? .on : .off
        }
        guard includeToggles else { return menu }
        menu.addSeparator()
        menu.addItem("Navigation pane", #selector(toggleNavigationPane(_:)), target: self).state = Prefs.showNavigationPane ? .on : .off
        menu.addItem("File name extensions", #selector(toggleExtensions(_:)), target: self).state = Prefs.showExtensions ? .on : .off
        menu.addItem("Hidden items", #selector(toggleHiddenItems(_:)), target: self, key: ".", modifiers: [.command, .shift])
            .state = Prefs.showHidden ? .on : .off
        return menu
    }

    func moreMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem("Select all", #selector(selectAll(_:)), target: self, key: "a", symbol: "checkmark.circle")
        menu.addItem("Select none", #selector(selectNone(_:)), target: self, symbol: "circle")
        menu.addItem("Invert selection", #selector(invertSelection(_:)), target: self, symbol: "circle.lefthalf.filled")
        menu.addSeparator()
        menu.addItem("Compress to ZIP file", #selector(compressSelection(_:)), target: self, symbol: "doc.zipper")
        menu.addItem("Copy as path", #selector(copyAsPath(_:)), target: self, symbol: "link")
        menu.addItem("Show in Finder", #selector(revealInFinder(_:)), target: self, symbol: "macwindow")
        menu.addSeparator()
        menu.addItem("Properties", #selector(showProperties(_:)), target: self, symbol: "info.circle")
        return menu
    }

    @objc func showNewMenu(_ sender: NSButton) { sender.popUpBelow(newMenu()) }
    @objc func showSortMenu(_ sender: NSButton) { sender.popUpBelow(sortMenu()) }
    @objc func showViewMenu(_ sender: NSButton) { sender.popUpBelow(viewMenu(includeToggles: true)) }
    @objc func showMoreMenu(_ sender: NSButton) { sender.popUpBelow(moreMenu()) }
}

// MARK: - Menu validation

extension ExplorerViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let hasSelection = !selectedItems.isEmpty
        let canWrite = FileManager.default.isWritableFile(atPath: model.folder.path)
        let explicit = menuItem.representedObject != nil
        // While typing in the address bar / search box, file shortcuts (⌘⌫, F2, ⌘O…) must reach the text field.
        let editingText = view.window?.firstResponder is NSText && menuItem.menu?.supermenu != nil
        let fileOnly: Set<Selector?> = [#selector(moveToTrash(_:)), #selector(deletePermanently(_:)),
                                        #selector(renameSelection(_:)), #selector(openSelection(_:)),
                                        #selector(selectNone(_:)), #selector(invertSelection(_:))]
        if editingText && fileOnly.contains(menuItem.action) { return false }
        switch menuItem.action {
        case #selector(copy(_:)), #selector(shareSelection(_:)):
            return hasSelection
        case #selector(cut(_:)):
            return hasSelection && canWrite
        case #selector(moveToTrash(_:)), #selector(deletePermanently(_:)), #selector(compressSelection(_:)):
            return (hasSelection || explicit) && canWrite
        case #selector(renameSelection(_:)):
            return selectedItems.count == 1 && canWrite
        case #selector(openSelection(_:)):
            return hasSelection
        case #selector(paste(_:)):
            return FileClipboard.shared.hasFiles && (canWrite || explicit)
        case #selector(newFolder(_:)), #selector(newTextDocument(_:)):
            return canWrite
        case #selector(goBack(_:)):
            return model.canGoBack
        case #selector(goForward(_:)):
            return model.canGoForward
        case #selector(goUp(_:)):
            return model.canGoUp
        case #selector(setViewModeFromMenu(_:)):
            menuItem.state = (menuItem.representedObject as? String) == viewMode.rawValue ? .on : .off
            return true
        case #selector(toggleHiddenItems(_:)):
            menuItem.state = Prefs.showHidden ? .on : .off
            return true
        case #selector(toggleExtensions(_:)):
            menuItem.state = Prefs.showExtensions ? .on : .off
            return true
        case #selector(toggleNavigationPane(_:)):
            menuItem.state = Prefs.showNavigationPane ? .on : .off
            return true
        default:
            return true
        }
    }
}

// MARK: - FileViewHost

extension ExplorerViewController: FileViewHost {
    var currentFolder: URL { model.folder }
    var showExtensions: Bool { Prefs.showExtensions }

    func isCut(_ url: URL) -> Bool { FileClipboard.shared.cutPaths.contains(url.path) }

    func fileViewSelectionDidChange(_ view: FileView) {
        updateStatus()
        updateCommandStates()
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
        }
    }

    func fileView(_ view: FileView, open items: [FileItem]) { openItems(items) }

    func fileView(_ view: FileView, menuFor clicked: FileItem?) -> NSMenu? {
        clicked == nil ? backgroundMenu() : itemMenu(for: selectedItems)
    }

    func fileView(_ view: FileView, rename item: FileItem, to newName: String) {
        performRename(item, to: newName)
    }

    func fileViewDidEndRenaming(_ view: FileView) { applyPendingChange() }

    func fileView(_ view: FileView, sortBy key: SortKey, ascending: Bool) {
        model.setSort(key, ascending: ascending)
    }

    func fileView(_ view: FileView, handleKey event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        switch event.keyCode {
        case KeyCode.returnKey, KeyCode.enter:
            if flags == .option { showProperties(nil) } else { openSelection(nil) } // Alt+Enter = Properties
            return true
        case KeyCode.backspace where flags.isEmpty:
            goBack(nil) // Windows: Backspace = Back
            return true
        case KeyCode.backspace where flags == .command:
            moveToTrash(nil)
            return true
        case KeyCode.backspace where flags == .shift:
            deletePermanently(nil)
            return true
        case KeyCode.forwardDelete:
            if flags.contains(.shift) { deletePermanently(nil) } else { moveToTrash(nil) }
            return true
        case KeyCode.f2:
            renameSelection(nil)
            return true
        case KeyCode.space where flags.isEmpty:
            toggleQuickLook()
            return true
        case KeyCode.down where flags == .command:
            openSelection(nil)
            return true
        default:
            return false
        }
    }

    /// Windows rules: same drive → move, other drive → copy; ⌥ forces copy, ⌘ forces move.
    func dragOperation(for urls: [URL], into folder: URL, info: NSDraggingInfo?) -> NSDragOperation {
        guard !urls.isEmpty, FileManager.default.isWritableFile(atPath: folder.path) else { return [] }
        if urls.contains(where: { folder.isDescendant(of: $0) }) { return [] }
        let flags = NSEvent.modifierFlags
        if urls.allSatisfy({ $0.deletingLastPathComponent().isSameFile(as: folder) }) {
            return flags.contains(.option) ? .copy : []
        }
        let mask = info?.draggingSourceOperationMask ?? [.copy, .move]
        var op: NSDragOperation
        if flags.contains(.option) {
            op = .copy
        } else if flags.contains(.command) {
            op = .move
        } else {
            let sameVolume = urls.first?.volumeIdentifier?.isEqual(folder.volumeIdentifier) ?? false
            op = sameVolume ? .move : .copy
        }
        if !mask.contains(op) { op = mask.contains(.copy) ? .copy : (mask.contains(.move) ? .move : []) }
        return op
    }

    func fileView(_ view: FileView, dropOperationFor urls: [URL], into folder: URL, info: NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: urls, into: folder, info: info)
    }

    func fileView(_ view: FileView, acceptDrop urls: [URL], into folder: URL, operation: NSDragOperation) -> Bool {
        transfer(urls, into: folder, move: operation == .move)
        return true
    }
}

// MARK: - Quick Look (Space)

extension ExplorerViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func toggleQuickLook() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists() && panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { selectedURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        selectedURLs[safe: index] as NSURL?
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // Let arrow keys move the selection in the file view while previewing.
        if event.type == .keyDown, [KeyCode.up, KeyCode.down, KeyCode.left, KeyCode.right].contains(event.keyCode) {
            current.view.window?.firstResponder?.keyDown(with: event)
            return true
        }
        return false
    }
}
