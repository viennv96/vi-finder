import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var eventMonitor: Any?
    private var pendingOpenURLs: [URL] = []
    private var pendingRevealURLs: [URL] = []
    private var launched = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenu.build()
        // "Reveal in file viewer" requests (sent when ViFinder is the NSFileViewer).
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleRevealEvent(_:reply:)),
            forEventClass: AEEventClass(kAEMiscStandards), andEventID: AEEventID(kAEMakeObjectsVisible))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { event in
            guard let controller = event.window?.windowController as? ExplorerWindowController else { return event }
            return controller.handle(event) ? nil : event
        }
        if pendingOpenURLs.isEmpty && pendingRevealURLs.isEmpty {
            ExplorerWindowController.openWindow(at: Places.home)
        } else {
            open(pendingOpenURLs)
            reveal(pendingRevealURLs)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    /// Folders dropped onto the Dock icon / `open -a ViFinder <folder>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        if launched { open(urls) } else { pendingOpenURLs.append(contentsOf: urls) }
    }

    /// Folders open in a window; files open their parent folder with the file selected.
    private func open(_ urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: url.path) {
                ExplorerWindowController.openWindow(at: url)
            } else {
                files.append(url)
            }
        }
        // Files from the same folder share one window with all of them selected.
        if !files.isEmpty { reveal(files) }
    }

    /// "Show in Finder": open each parent folder once and select the requested items.
    private func reveal(_ urls: [URL]) {
        let groups = Dictionary(grouping: urls.map(\.standardizedFileURL)) { $0.deletingLastPathComponent() }
        for (folder, items) in groups {
            let controller = ExplorerWindowController.openWindow(at: folder)
            controller.explorer.model.reload(select: Set(items))
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func handleRevealEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let direct = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        var urls: [URL] = []
        if direct.numberOfItems > 0 {
            for index in 1...direct.numberOfItems {
                if let url = direct.atIndex(index)?.fileURLValue { urls.append(url) }
            }
        } else if let url = direct.fileURLValue {
            urls.append(url)
        }
        guard !urls.isEmpty else { return }
        if launched { reveal(urls) } else { pendingRevealURLs.append(contentsOf: urls) }
    }

    // MARK: Default file browser

    @objc func toggleDefaultFileBrowser(_ sender: Any?) {
        if DefaultFileBrowser.isDefault {
            DefaultFileBrowser.restoreFinder { [weak self] error in
                self?.report(error, success: "Finder is the default file browser again.")
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Make ViFinder the default file browser?"
        alert.informativeText = """
            Folders opened from other apps and from Terminal (open .) will open in ViFinder, \
            and apps that support it will use ViFinder for "Show in Finder".

            macOS keeps Finder for the Desktop, Dock and Trash. You can switch back any time \
            from the ViFinder menu.
            """
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        DefaultFileBrowser.makeDefault { [weak self] error in
            self?.report(error, success: "ViFinder is now the default file browser.")
        }
    }

    private func report(_ error: Error?, success: String) {
        let alert = error.map { NSAlert(error: $0) } ?? {
            let a = NSAlert()
            a.messageText = success
            return a
        }()
        alert.runModal()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem("New Window", #selector(newWindow(_:)), target: self)
        return menu
    }

    // MARK: Fallback actions (used when no explorer window is key)

    @objc func newWindow(_ sender: Any?) {
        let folder = (NSApp.keyWindow?.windowController as? ExplorerWindowController)?.explorer.model.folder
            ?? Places.home
        ExplorerWindowController.openWindow(at: folder)
    }

    @objc func newTab(_ sender: Any?) { newWindow(sender) }

    @objc func goToLocation(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { ExplorerWindowController.openWindow(at: url) }
    }

    @objc func setDefaultTerminal(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Prefs.terminalBundleID = id }
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleDefaultFileBrowser(_:)) {
            let isDefault = DefaultFileBrowser.isDefault
            menuItem.title = isDefault ? "Restore Finder as Default File Browser" : "Set ViFinder as Default File Browser…"
            return DefaultFileBrowser.isAvailable
        }
        return true
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilds the "Default Terminal" submenu each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = TerminalLauncher.preferred.bundleID
        for app in TerminalLauncher.installedTerminals {
            let item = menu.addItem(app.name, #selector(setDefaultTerminal(_:)), target: self, represented: app.bundleID)
            item.image = app.icon
            item.state = app.bundleID == current ? .on : .off
        }
    }
}
