import AppKit

/// Implemented by the explorer controller; receives events from whichever file view is active.
protocol FileViewHost: AnyObject {
    var currentFolder: URL { get }
    var showExtensions: Bool { get }
    func isCut(_ url: URL) -> Bool
    func fileViewSelectionDidChange(_ view: FileView)
    func fileView(_ view: FileView, open items: [FileItem])
    func fileView(_ view: FileView, menuFor clicked: FileItem?) -> NSMenu?
    func fileView(_ view: FileView, rename item: FileItem, to newName: String)
    func fileViewDidEndRenaming(_ view: FileView)
    /// Return true if the key was handled.
    func fileView(_ view: FileView, handleKey event: NSEvent) -> Bool
    func fileView(_ view: FileView, sortBy key: SortKey, ascending: Bool)
    func fileView(_ view: FileView, dropOperationFor urls: [URL], into folder: URL, info: NSDraggingInfo) -> NSDragOperation
    func fileView(_ view: FileView, acceptDrop urls: [URL], into folder: URL, operation: NSDragOperation) -> Bool
}

/// Common interface of the Details view and the Icons views.
protocol FileView: AnyObject {
    var view: NSView { get }
    var items: [FileItem] { get }
    var selectedItems: [FileItem] { get }
    var isRenaming: Bool { get }
    func display(_ items: [FileItem], selecting: Set<URL>, scrollToTop: Bool)
    func select(_ urls: Set<URL>)
    func selectAll()
    func selectNone()
    func invertSelection()
    func beginRename(_ url: URL)
    func focus()
    /// Redraw rows without changing data (cut state, extensions).
    func refreshAppearance()
    func setSortIndicator(_ key: SortKey, ascending: Bool)
    /// Non-nil while showing search results (Details view adds a "Folder" column).
    func setSearchRoot(_ root: URL?)
}

enum DragSupport {
    static func fileURLs(from info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

/// Inline rename helper shared by both views: selects the base name (without extension) like Windows.
enum RenameEditing {
    static func selectBaseName(in field: NSTextField) {
        guard let editor = field.currentEditor() else { return }
        let name = field.stringValue as NSString
        let ext = name.pathExtension
        if !ext.isEmpty && name.length > ext.count + 1 {
            editor.selectedRange = NSRange(location: 0, length: name.length - ext.count - 1)
        } else {
            editor.selectAll(nil)
        }
    }
}
