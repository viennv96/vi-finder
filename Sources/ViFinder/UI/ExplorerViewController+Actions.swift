import AppKit

/// Wraps "open this folder with that app" for menu items.
final class AppTarget: NSObject {
    let app: ExternalApp?
    let appURL: URL?
    let urls: [URL]
    init(app: ExternalApp? = nil, appURL: URL? = nil, urls: [URL]) {
        self.app = app
        self.appURL = appURL ?? app?.appURL
        self.urls = urls
    }
}

extension ExplorerViewController {
    // MARK: Navigation

    @objc func goBack(_ sender: Any?) { model.goBack(); current.focus() }
    @objc func goForward(_ sender: Any?) { model.goForward(); current.focus() }
    @objc func goUp(_ sender: Any?) { model.goUp(); current.focus() }
    @objc func refresh(_ sender: Any?) { model.reload() }

    @objc func goToLocation(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { navigate(to: url) }
    }

    @objc func focusAddressBar(_ sender: Any?) { addressBar.beginEditing() }

    /// "Network" → mount an SMB / AFP / NFS share (like Windows' "Map network drive").
    @objc func connectToServer(_ sender: Any?) {
        sidebar.highlight(model.folder)
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Connect to Server"
        alert.informativeText = "Enter the server address, for example smb://192.168.1.10/Share"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.stringValue = UserDefaults.standard.string(forKey: "lastServerAddress") ?? "smb://"
        field.placeholderString = "smb://server/share"
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            var text = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !text.contains("://") { text = "smb://" + text }
            guard let url = URL(string: text), url.host != nil else { return NSSound.beep() }
            UserDefaults.standard.set(text, forKey: "lastServerAddress")
            NSWorkspace.shared.open(url)
        }
    }
    @objc func focusSearch(_ sender: Any?) { view.window?.makeFirstResponder(searchField) }

    // MARK: Open

    @objc func openSelection(_ sender: Any?) { openItems(selectedItems) }

    func openItems(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        var folders: [URL] = []
        for item in items {
            if item.isFolder {
                folders.append(item.url)
            } else if let target = resolveAlias(item.url), isNavigableFolder(target) {
                folders.append(target)
            } else {
                NSWorkspace.shared.open(item.url)
            }
        }
        if folders.count == 1 {
            navigate(to: folders[0])
        } else {
            folders.forEach { windowController?.openNewTab(at: $0) }
        }
    }

    private func resolveAlias(_ url: URL) -> URL? {
        guard (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true else { return nil }
        return try? URL(resolvingAliasFileAt: url)
    }

    private func isNavigableFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            && !NSWorkspace.shared.isFilePackage(atPath: url.path)
    }

    @objc func openInNewTab(_ sender: Any?) {
        let folders = targetURLs(sender).filter(isNavigableFolder)
        (folders.isEmpty ? [model.folder] : folders).forEach { windowController?.openNewTab(at: $0) }
    }

    @objc func openInNewWindow(_ sender: Any?) {
        let folders = targetURLs(sender).filter(isNavigableFolder)
        (folders.isEmpty ? [model.folder] : folders).forEach { ExplorerWindowController.openWindow(at: $0) }
    }

    @objc func openWithApp(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? AppTarget, let appURL = target.appURL else { return }
        NSWorkspace.shared.open(target.urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func openWithOther(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? AppTarget, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        panel.message = "Choose an app to open the selected items"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let app = panel.url else { return }
            NSWorkspace.shared.open(target.urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Folder the terminal should open in: explicit menu target, a single selected folder, or the current folder.
    private func terminalFolder(_ sender: Any?) -> URL {
        if let item = sender as? NSMenuItem {
            if let url = item.representedObject as? URL { return url }
            if let target = item.representedObject as? AppTarget, let url = target.urls.first { return url }
        }
        let selection = selectedItems
        if selection.count == 1, selection[0].isFolder { return selection[0].url }
        return model.folder
    }

    @objc func openInTerminal(_ sender: Any?) {
        TerminalLauncher.open(terminalFolder(sender))
    }

    @objc func openInSpecificApp(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? AppTarget, let app = target.app else { return }
        TerminalLauncher.open(target.urls.first ?? model.folder, with: app)
    }

    @objc func setDefaultTerminal(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Prefs.terminalBundleID = id }
    }

    @objc func revealInFinder(_ sender: Any?) {
        let urls = targetURLs(sender)
        DefaultFileBrowser.revealInFinder(urls.isEmpty ? [model.folder] : urls)
    }

    // MARK: Clipboard

    /// URLs a menu action applies to: menu item target if any, else the selection.
    func targetURLs(_ sender: Any?) -> [URL] {
        if let item = sender as? NSMenuItem {
            if let urls = item.representedObject as? [URL] { return urls }
            if let url = item.representedObject as? URL { return [url] }
        }
        return selectedURLs
    }

    @objc func copy(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return NSSound.beep() }
        FileClipboard.shared.write(urls, operation: .copy)
    }

    @objc func cut(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return NSSound.beep() }
        FileClipboard.shared.write(urls, operation: .cut)
    }

    @objc func paste(_ sender: Any?) {
        let destination = (sender as? NSMenuItem)?.representedObject as? URL ?? model.folder
        guard let content = FileClipboard.shared.read() else { return NSSound.beep() }
        let isCut = content.operation == .cut
        transfer(content.urls, into: destination, move: isCut, clearClipboardAfter: isCut)
    }

    @objc func copyAsPath(_ sender: Any?) {
        let urls = targetURLs(sender)
        let paths = (urls.isEmpty ? [model.folder] : urls).map(\.path)
        FileClipboard.shared.writeText(paths.joined(separator: "\n"))
    }

    /// Copy / move with Windows-like conflict handling and progress in the status bar.
    func transfer(_ urls: [URL], into folder: URL, move: Bool, clearClipboardAfter: Bool = false) {
        do {
            guard let steps = try FileOps.planTransfer(urls, into: folder, move: move,
                                                       resolve: { [weak self] count in self?.askConflict(count) }),
                  !steps.isEmpty else { return }
            let verb = move ? "Moving" : "Copying"
            FileOps.execute(steps, move: move, progress: { [weak self] done, total, name in
                self?.statusBar.setProgress("\(verb) \(done + 1) of \(total): \(name)")
            }, completion: { [weak self] created, errors in
                guard let self else { return }
                self.statusBar.setProgress(nil)
                if clearClipboardAfter && errors.isEmpty { FileClipboard.shared.clearAfterCutPaste() }
                if folder.isSameFile(as: self.model.folder) {
                    self.model.reload(select: Set(created))
                } else {
                    self.model.reload()
                }
                self.present(errors)
            })
        } catch {
            present([error])
        }
    }

    private func askConflict(_ count: Int) -> FileOps.ConflictChoice? {
        let alert = NSAlert()
        alert.messageText = count == 1
            ? "The destination already has a file with the same name"
            : "The destination has \(count) files with the same names"
        alert.informativeText = "Replaced items are moved to the Trash."
        alert.addButton(withTitle: "Replace the file\(count == 1 ? "" : "s")")
        alert.addButton(withTitle: "Skip \(count == 1 ? "this file" : "these files")")
        alert.addButton(withTitle: "Keep both")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .replace
        case .alertSecondButtonReturn: return .skip
        case .alertThirdButtonReturn: return .keepBoth
        default: return nil
        }
    }

    func present(_ errors: [Error]) {
        guard let first = errors.first else { return }
        let alert = NSAlert(error: first)
        if errors.count > 1 { alert.informativeText += "\n\n(\(errors.count - 1) more error(s))" }
        if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    // MARK: Create / rename / delete

    @objc func newFolder(_ sender: Any?) {
        do {
            let url = try FileOps.createFolder(in: model.folder)
            model.reload(select: [url], rename: url)
        } catch { present([error]) }
    }

    @objc func newTextDocument(_ sender: Any?) {
        do {
            let url = try FileOps.createTextFile(in: model.folder)
            model.reload(select: [url], rename: url)
        } catch { present([error]) }
    }

    @objc func renameSelection(_ sender: Any?) {
        guard let item = selectedItems.first else { return NSSound.beep() }
        current.beginRename(item.url)
    }

    func performRename(_ item: FileItem, to input: String) {
        var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !Prefs.showExtensions && !item.isFolder && !item.pathExtension.isEmpty {
            name += "." + item.pathExtension
        } else if !item.isFolder {
            let oldExt = item.pathExtension.lowercased()
            let newExt = (name as NSString).pathExtension.lowercased()
            if oldExt != newExt {
                let alert = NSAlert()
                alert.messageText = "Rename"
                alert.informativeText = "If you change a file name extension, the file might become unusable.\n\nAre you sure you want to change it?"
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "No")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
        }
        do {
            let newURL = try FileOps.rename(item.url, to: name)
            IconProvider.invalidate(item.url)
            model.reload(select: [newURL])
        } catch {
            present([error])
        }
    }

    /// Delete → Trash (no confirmation, like Windows' Recycle Bin).
    @objc func moveToTrash(_ sender: Any?) {
        let urls = targetURLs(sender)
        guard !urls.isEmpty else { return NSSound.beep() }
        FileOps.moveToTrash(urls) { [weak self] errors in
            self?.model.reload()
            self?.present(errors)
        }
    }

    /// Shift+Delete → permanent delete with confirmation.
    @objc func deletePermanently(_ sender: Any?) {
        let urls = targetURLs(sender)
        guard !urls.isEmpty else { return NSSound.beep() }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = urls.count == 1
            ? "Are you sure you want to permanently delete \"\(urls[0].lastPathComponent)\"?"
            : "Are you sure you want to permanently delete these \(urls.count) items?"
        alert.informativeText = "This action can't be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        FileOps.deletePermanently(urls) { [weak self] errors in
            self?.model.reload()
            self?.present(errors)
        }
    }

    // MARK: Misc

    @objc func shareSelection(_ sender: Any?) {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        let anchor: NSView = commandBar.shareButton.window != nil && !commandBar.shareButton.isHiddenOrHasHiddenAncestor
            ? commandBar.shareButton : current.view
        picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    @objc func compressSelection(_ sender: Any?) {
        let urls = targetURLs(sender)
        guard !urls.isEmpty else { return }
        statusBar.setProgress("Compressing…")
        FileOps.compress(urls, in: model.folder) { [weak self] zip, error in
            self?.statusBar.setProgress(nil)
            if let error { self?.present([error]) }
            if let zip { self?.model.reload(select: [zip], rename: zip) }
        }
    }

    @objc func extractSelection(_ sender: Any?) {
        let zips = targetURLs(sender).filter { $0.pathExtension.lowercased() == "zip" }
        guard let zip = zips.first else { return }
        statusBar.setProgress("Extracting \(zip.lastPathComponent)…")
        FileOps.extract(zip) { [weak self] folder, error in
            self?.statusBar.setProgress(nil)
            if let error { self?.present([error]) }
            if let folder { self?.model.reload(select: [folder]) }
        }
    }

    @objc func showProperties(_ sender: Any?) {
        let urls = targetURLs(sender)
        PropertiesWindowController.show(for: urls.isEmpty ? [model.folder] : urls)
    }

    @objc override func selectAll(_ sender: Any?) {
        current.selectAll()
    }

    @objc func selectNone(_ sender: Any?) { current.selectNone() }
    @objc func invertSelection(_ sender: Any?) { current.invertSelection() }

    // MARK: View / sort

    @objc func setViewModeFromMenu(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = ViewMode(rawValue: raw) { setViewMode(mode) }
    }

    @objc func setViewModeFromStatusBar(_ sender: NSButton) {
        setViewMode(sender.tag == 0 ? .details : .largeIcons)
    }

    @objc func cycleViewMode(_ sender: Any?) {
        let all = ViewMode.allCases
        let next = all[(all.firstIndex(of: viewMode)! + 1) % all.count]
        setViewMode(next)
    }

    @objc func sortFromMenu(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let key = SortKey(rawValue: raw) {
            applySort(key, ascending: model.sortKey == key ? model.ascending : (key == .name || key == .type))
        } else {
            applySort(model.sortKey, ascending: sender.tag == 1)
        }
    }

    func applySort(_ key: SortKey, ascending: Bool) {
        model.setSort(key, ascending: ascending)
        current.setSortIndicator(key, ascending: ascending)
    }

    @objc func toggleHiddenItems(_ sender: Any?) { Prefs.showHidden.toggle() }
    @objc func toggleExtensions(_ sender: Any?) { Prefs.showExtensions.toggle() }
    @objc func toggleNavigationPane(_ sender: Any?) { Prefs.showNavigationPane.toggle() }
}
