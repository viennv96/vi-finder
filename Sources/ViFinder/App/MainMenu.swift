import AppKit

/// Menu bar. Actions travel the responder chain to the active ExplorerViewController.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("ViFinder", appMenu()))
        main.addItem(submenu("File", fileMenu()))
        main.addItem(submenu("Edit", editMenu()))
        main.addItem(submenu("View", viewMenu()))
        main.addItem(submenu("Go", goMenu()))
        let window = windowMenu()
        main.addItem(submenu("Window", window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu("Help", help))
        NSApp.helpMenu = help
        return main
    }

    private typealias E = ExplorerViewController

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        menu.title = title
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem("About ViFinder", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: nil)
        m.addSeparator()
        let terminal = NSMenuItem(title: "Default Terminal", action: nil, keyEquivalent: "")
        let terminalMenu = NSMenu()
        terminalMenu.delegate = NSApp.delegate as? AppDelegate
        terminal.submenu = terminalMenu
        m.addItem(terminal)
        m.addItem("Set ViFinder as Default File Browser…", #selector(AppDelegate.toggleDefaultFileBrowser(_:)), target: NSApp.delegate)
        m.addSeparator()
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu()
        NSApp.servicesMenu = services.submenu
        m.addItem(services)
        m.addSeparator()
        m.addItem("Hide ViFinder", #selector(NSApplication.hide(_:)), target: nil, key: "h")
        m.addItem("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), target: nil, key: "h", modifiers: [.command, .option])
        m.addItem("Show All", #selector(NSApplication.unhideAllApplications(_:)), target: nil)
        m.addSeparator()
        m.addItem("Quit ViFinder", #selector(NSApplication.terminate(_:)), target: nil, key: "q")
        return m
    }

    private static func fileMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem("New Window", #selector(AppDelegate.newWindow(_:)), target: nil, key: "n")
        m.addItem("New Tab", #selector(ExplorerWindowController.newTab(_:)), target: nil, key: "t")
        m.addItem("New Folder", #selector(E.newFolder(_:)), target: nil, key: "n", modifiers: [.command, .shift])
        m.addItem("New Text Document", #selector(E.newTextDocument(_:)), target: nil, key: "n", modifiers: [.command, .option])
        m.addSeparator()
        m.addItem("Open", #selector(E.openSelection(_:)), target: nil, key: "o")
        m.addItem("Open in New Tab", #selector(E.openInNewTab(_:)), target: nil)
        m.addItem("Open in New Window", #selector(E.openInNewWindow(_:)), target: nil)
        m.addItem("Open in Terminal", #selector(E.openInTerminal(_:)), target: nil, key: "t", modifiers: [.command, .option])
        m.addSeparator()
        m.addItem("Rename", #selector(E.renameSelection(_:)), target: nil, key: FunctionKey.f2, modifiers: [])
        m.addItem("Move to Trash", #selector(E.moveToTrash(_:)), target: nil, key: FunctionKey.backspace)
        m.addItem("Delete Permanently…", #selector(E.deletePermanently(_:)), target: nil, key: FunctionKey.backspace, modifiers: [.command, .option])
        m.addItem("Compress to ZIP File", #selector(E.compressSelection(_:)), target: nil)
        m.addItem("Show in Finder", #selector(E.revealInFinder(_:)), target: nil, key: "r", modifiers: [.command, .shift])
        m.addSeparator()
        m.addItem("Properties", #selector(E.showProperties(_:)), target: nil, key: "i")
        m.addSeparator()
        m.addItem("Close Tab", #selector(ExplorerWindowController.closeCurrentTab(_:)), target: nil, key: "w")
        m.addItem("Close Window", #selector(NSWindow.performClose(_:)), target: nil, key: "w", modifiers: [.command, .shift])
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem("Undo", Selector(("undo:")), target: nil, key: "z")
        m.addItem("Redo", Selector(("redo:")), target: nil, key: "z", modifiers: [.command, .shift])
        m.addSeparator()
        m.addItem("Cut", #selector(NSText.cut(_:)), target: nil, key: "x")
        m.addItem("Copy", #selector(NSText.copy(_:)), target: nil, key: "c")
        m.addItem("Paste", #selector(NSText.paste(_:)), target: nil, key: "v")
        m.addItem("Copy as Path", #selector(E.copyAsPath(_:)), target: nil, key: "c", modifiers: [.command, .option])
        m.addItem("Select All", #selector(NSText.selectAll(_:)), target: nil, key: "a")
        m.addItem("Select None", #selector(E.selectNone(_:)), target: nil, key: "a", modifiers: [.command, .option])
        m.addItem("Invert Selection", #selector(E.invertSelection(_:)), target: nil, key: "i", modifiers: [.command, .shift])
        m.addSeparator()
        m.addItem("Search", #selector(E.focusSearch(_:)), target: nil, key: "f")
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu()
        for mode in ViewMode.menuOrder {
            m.addItem(mode.title, #selector(E.setViewModeFromMenu(_:)), target: nil, key: mode.shortcut,
                      represented: mode.rawValue)
        }
        m.addSeparator()
        let sort = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for key in SortKey.allCases {
            sortMenu.addItem(key.title, #selector(E.sortFromMenu(_:)), target: nil, represented: key.rawValue)
        }
        sortMenu.addSeparator()
        sortMenu.addItem("Ascending", #selector(E.sortFromMenu(_:)), target: nil, tag: 1)
        sortMenu.addItem("Descending", #selector(E.sortFromMenu(_:)), target: nil, tag: 0)
        sort.submenu = sortMenu
        m.addItem(sort)
        m.addSeparator()
        m.addItem("Navigation Pane", #selector(E.toggleNavigationPane(_:)), target: nil, key: "s", modifiers: [.command, .control])
        m.addItem("Preview Pane", #selector(E.togglePreviewPane(_:)), target: nil, key: "p", modifiers: [.command, .shift])
        m.addItem("File Name Extensions", #selector(E.toggleExtensions(_:)), target: nil)
        m.addItem("Hidden Items", #selector(E.toggleHiddenItems(_:)), target: nil, key: ".", modifiers: [.command, .shift])
        m.addSeparator()
        m.addItem("Refresh", #selector(E.refresh(_:)), target: nil, key: "r")
        m.addSeparator()
        return m
    }

    private static func goMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem("Back", #selector(E.goBack(_:)), target: nil, key: "[")
        m.addItem("Forward", #selector(E.goForward(_:)), target: nil, key: "]")
        m.addItem("Up", #selector(E.goUp(_:)), target: nil, key: FunctionKey.up)
        m.addSeparator()
        let home = Places.home
        func dir(_ d: FileManager.SearchPathDirectory) -> URL { Places.user(d) }
        let places: [(String, URL, String, NSEvent.ModifierFlags)] = [
            ("Home", home, "h", [.command, .shift]),
            ("Desktop", dir(.desktopDirectory), "d", [.command, .shift]),
            ("Documents", dir(.documentDirectory), "o", [.command, .shift]),
            ("Downloads", dir(.downloadsDirectory), "l", [.command, .option]),
            ("Applications", URL(fileURLWithPath: "/Applications"), "a", [.command, .shift]),
            ("This Mac (/)", URL(fileURLWithPath: "/"), "c", [.command, .shift]),
        ]
        for (title, url, key, mods) in places {
            m.addItem(title, #selector(E.goToLocation(_:)), target: nil, key: key, modifiers: mods, represented: url)
        }
        m.addSeparator()
        m.addItem("Go to Address…", #selector(E.focusAddressBar(_:)), target: nil, key: "l")
        m.addItem("Go to Folder…", #selector(E.focusAddressBar(_:)), target: nil, key: "g", modifiers: [.command, .shift])
        m.addItem("Connect to Server…", #selector(E.connectToServer(_:)), target: nil, key: "k")
        return m
    }

    private static func windowMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem("Minimize", #selector(NSWindow.performMiniaturize(_:)), target: nil, key: "m")
        m.addItem("Zoom", #selector(NSWindow.performZoom(_:)), target: nil)
        m.addSeparator()
        m.addItem("Show Next Tab", #selector(ExplorerWindowController.selectNextTab(_:)), target: nil, key: "]", modifiers: [.command, .shift])
        m.addItem("Show Previous Tab", #selector(ExplorerWindowController.selectPreviousTab(_:)), target: nil, key: "[", modifiers: [.command, .shift])
        m.addSeparator()
        m.addItem("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), target: nil)
        return m
    }
}
