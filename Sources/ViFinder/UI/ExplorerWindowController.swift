import AppKit

/// One Explorer window with its own Windows 11-style tab strip in the title bar.
final class ExplorerWindowController: NSWindowController, NSWindowDelegate {
    private(set) static var all: [ExplorerWindowController] = []
    private let container = TabsContainerViewController()
    private(set) var tabs: [ExplorerViewController] = []
    private(set) var selectedIndex = 0

    var explorer: ExplorerViewController { tabs[selectedIndex] }

    @discardableResult
    static func openWindow(at url: URL) -> ExplorerWindowController {
        let reference = NSApp.keyWindow ?? all.last?.window
        let controller = ExplorerWindowController(url: url)
        all.append(controller)
        if let reference, let window = controller.window {
            window.setFrame(reference.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: reference.frame.minX, y: reference.frame.maxY)))
        }
        controller.showWindow(nil)
        return controller
    }

    init(url: URL) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .disallowed
        window.contentViewController = container
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        if ExplorerWindowController.all.isEmpty {
            window.center()
            window.setFrameAutosaveName("ViFinder.MainWindow")
        }
        container.strip.onSelect = { [weak self] index in self?.selectTab(index) }
        container.strip.onClose = { [weak self] index in self?.removeTab(at: index) }
        container.strip.onNew = { [weak self] in self?.newTab(nil) }
        container.strip.onMenu = { [weak self] index in self?.menu(forTab: index) }
        addTab(at: url)
        positionTrafficLights()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tabs

    func addTab(at url: URL, select: Bool = true) {
        let tab = ExplorerViewController(url: url)
        tab.windowController = self
        let insertAt = tabs.isEmpty ? 0 : selectedIndex + 1
        tabs.insert(tab, at: insertAt)
        if select || tabs.count == 1 {
            selectTab(insertAt)
        } else {
            if insertAt <= selectedIndex { selectedIndex += 1 }
            _ = tab.view // load so the model starts and the tab gets a title
            refreshStrip()
        }
    }

    func openNewTab(at url: URL) { addTab(at: url) }

    func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
        container.show(tabs[index])
        refreshStrip()
        tabs[index].current?.focus()
        tabs[index].updateCommandStates()
    }

    func removeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        if tabs.count == 1 {
            window?.performClose(nil)
            return
        }
        let tab = tabs.remove(at: index)
        container.remove(tab)
        if selectedIndex >= tabs.count { selectedIndex = tabs.count - 1 }
        else if index < selectedIndex { selectedIndex -= 1 }
        selectTab(selectedIndex)
    }

    /// Called by a tab when its folder changes.
    func tabDidUpdate(_ tab: ExplorerViewController) {
        refreshStrip()
    }

    private func refreshStrip() {
        let items = tabs.map { tab -> (title: String, icon: NSImage, tooltip: String) in
            let url = tab.model.folder
            return (url.displayName, IconProvider.icon(for: url), url.path)
        }
        container.strip.setTabs(items, selected: selectedIndex)
        window?.title = tabs[safe: selectedIndex]?.model.folder.displayName ?? "ViFinder"
    }

    private func menu(forTab index: Int) -> NSMenu {
        let menu = NSMenu()
        menu.addItem("New tab", #selector(newTab(_:)), target: self, key: "t")
        menu.addItem("Duplicate tab", #selector(duplicateTab(_:)), target: self, tag: index)
        menu.addItem("Move to new window", #selector(moveTabToNewWindow(_:)), target: self, tag: index)
        menu.addSeparator()
        menu.addItem("Close tab", #selector(closeTabFromMenu(_:)), target: self, key: "w", tag: index)
        menu.addItem("Close other tabs", #selector(closeOtherTabs(_:)), target: self, tag: index).isEnabled = tabs.count > 1
        menu.addItem("Close tabs to the right", #selector(closeTabsToRight(_:)), target: self, tag: index)
            .isEnabled = index < tabs.count - 1
        return menu
    }

    // MARK: Tab actions (menu bar / shortcuts)

    @objc func newTab(_ sender: Any?) { addTab(at: explorer.model.folder) }
    @objc func closeCurrentTab(_ sender: Any?) { removeTab(at: selectedIndex) }
    @objc func selectNextTab(_ sender: Any?) { selectTab((selectedIndex + 1) % tabs.count) }
    @objc func selectPreviousTab(_ sender: Any?) { selectTab((selectedIndex - 1 + tabs.count) % tabs.count) }

    @objc private func duplicateTab(_ sender: NSMenuItem) {
        guard let tab = tabs[safe: sender.tag] else { return }
        selectedIndex = sender.tag
        addTab(at: tab.model.folder)
    }

    @objc private func moveTabToNewWindow(_ sender: NSMenuItem) {
        guard let tab = tabs[safe: sender.tag] else { return }
        let folder = tab.model.folder
        ExplorerWindowController.openWindow(at: folder)
        if tabs.count > 1 { removeTab(at: sender.tag) }
    }

    @objc private func closeTabFromMenu(_ sender: NSMenuItem) { removeTab(at: sender.tag) }

    @objc private func closeOtherTabs(_ sender: NSMenuItem) {
        guard let keep = tabs[safe: sender.tag] else { return }
        for tab in tabs where tab !== keep { container.remove(tab) }
        tabs = [keep]
        selectTab(0)
    }

    @objc private func closeTabsToRight(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < tabs.count - 1 else { return }
        for tab in tabs[(index + 1)...] { container.remove(tab) }
        tabs.removeSubrange((index + 1)...)
        selectTab(min(selectedIndex, index))
    }

    // MARK: Window

    /// Vertically centre the traffic lights in the taller tab strip.
    private func positionTrafficLights() {
        guard let window, let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let y = titlebar.bounds.height - TabStripView.height / 2 - close.frame.height / 2
        for (index, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            button.setFrameOrigin(NSPoint(x: 14 + CGFloat(index) * 20, y: y))
        }
    }

    func windowDidResize(_ notification: Notification) { positionTrafficLights() }
    func windowDidEndLiveResize(_ notification: Notification) { positionTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { positionTrafficLights() }

    func windowWillClose(_ notification: Notification) {
        ExplorerWindowController.all.removeAll { $0 === self }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        positionTrafficLights()
        explorer.updateCommandStates()
    }

    // MARK: Windows-style shortcuts that menus can't express

    /// Returns true if the event was consumed.
    func handle(_ event: NSEvent) -> Bool {
        if event.type == .otherMouseDown {
            // Mouse side buttons: back / forward.
            if event.buttonNumber == 3 { explorer.goBack(nil); return true }
            if event.buttonNumber == 4 { explorer.goForward(nil); return true }
            return false
        }
        guard event.type == .keyDown else { return false }
        let editingText = window?.firstResponder is NSText
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch (event.keyCode, flags) {
        case (KeyCode.tab, .control): selectNextTab(nil); return true
        case (KeyCode.tab, [.control, .shift]): selectPreviousTab(nil); return true
        case (KeyCode.left, .option) where !editingText: explorer.goBack(nil); return true
        case (KeyCode.right, .option) where !editingText: explorer.goForward(nil); return true
        case (KeyCode.up, .option) where !editingText: explorer.goUp(nil); return true
        case (KeyCode.f5, []): explorer.refresh(nil); return true
        case (KeyCode.d, .option) where !editingText: explorer.focusAddressBar(nil); return true
        default: break
        }

        // Ctrl-based Windows shortcuts (Cmd versions live in the menu bar).
        guard flags.contains(.control), !flags.contains(.command), !editingText else { return false }
        let shift = flags.contains(.shift)
        switch key {
        case "c" where shift: explorer.copyAsPath(nil)
        case "c": explorer.copy(nil)
        case "x": explorer.cut(nil)
        case "v": explorer.paste(nil)
        case "a": explorer.selectAll(nil)
        case "n" where shift: explorer.newFolder(nil)
        case "n": ExplorerWindowController.openWindow(at: explorer.model.folder)
        case "t": newTab(nil)
        case "w": closeCurrentTab(nil)
        case "l": explorer.focusAddressBar(nil)
        case "f", "e": explorer.focusSearch(nil)
        case "r": explorer.refresh(nil)
        default: return false
        }
        return true
    }
}
