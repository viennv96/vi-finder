import AppKit

/// NSTableView that forwards keys and context menus to the host.
final class FileTableView: NSTableView {
    var keyHandler: ((NSEvent) -> Bool)?
    var menuProvider: ((Int) -> NSMenu?)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            if !selectedRowIndexes.contains(row) {
                selectRowIndexes([row], byExtendingSelection: false)
            }
        } else {
            deselectAll(nil)
        }
        return menuProvider?(row)
    }
}

/// Name cell: icon, name and the file's tag dots right after the name (like Finder).
final class NameCellView: NSTableCellView {
    let dots = TagDotsView()
}

/// Windows Explorer "Details" view: Name | Date modified | Type | Size.
final class DetailsViewController: NSViewController, FileView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Column: String {
        case name, folder, dateModified, type, size
    }

    weak var host: FileViewHost?
    private(set) var items: [FileItem] = []
    private let tableView = FileTableView()
    private let scrollView = NSScrollView()
    private var updatingSort = false
    private var searchRoot: URL?

    private var renamingItem: FileItem?
    private weak var renamingField: NSTextField?
    private var renameCancelled = false

    var isRenaming: Bool { renamingItem != nil }

    var selectedItems: [FileItem] {
        tableView.selectedRowIndexes.compactMap { items[safe: $0] }
    }

    override func loadView() {
        addColumn(.name, "Name", width: 320, min: 120)
        addColumn(.folder, "Folder", width: 260, min: 80)
        if let folder = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Column.folder.rawValue)) {
            folder.sortDescriptorPrototype = nil
            folder.isHidden = true
        }
        addColumn(.dateModified, "Date modified", width: 150, min: 80)
        addColumn(.type, "Type", width: 160, min: 60)
        addColumn(.size, "Size", width: 90, min: 50, alignment: .right)

        tableView.style = .fullWidth
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.autosaveName = "ViFinder.DetailsColumns"
        tableView.autosaveTableColumns = true
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move, .link], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.keyHandler = { [weak self] event in
            guard let self, let host = self.host else { return false }
            return host.fileView(self, handleKey: event)
        }
        tableView.menuProvider = { [weak self] row in
            guard let self, let host = self.host else { return nil }
            return host.fileView(self, menuFor: self.items[safe: row])
        }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        view = scrollView
    }

    private func addColumn(_ id: Column, _ title: String, width: CGFloat, min: CGFloat,
                           alignment: NSTextAlignment = .left) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id.rawValue))
        column.title = title
        column.width = width
        column.minWidth = min
        column.headerCell.alignment = alignment
        column.sortDescriptorPrototype = NSSortDescriptor(key: id.rawValue, ascending: true)
        tableView.addTableColumn(column)
    }

    // MARK: FileView

    func display(_ items: [FileItem], selecting: Set<URL>, scrollToTop: Bool) {
        self.items = items
        tableView.reloadData()
        let paths = Set(selecting.map { $0.standardizedFileURL.path })
        let indexes = IndexSet(items.indices.filter { paths.contains(items[$0].url.path) })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        if let first = indexes.first {
            tableView.scrollRowToVisible(first)
        } else if scrollToTop {
            tableView.scroll(.zero)
        }
    }

    func select(_ urls: Set<URL>) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        let indexes = IndexSet(items.indices.filter { paths.contains(items[$0].url.path) })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        if let first = indexes.first { tableView.scrollRowToVisible(first) }
    }

    func selectAll() { tableView.selectAll(nil) }
    func selectNone() { tableView.deselectAll(nil) }

    func invertSelection() {
        let all = IndexSet(integersIn: 0..<items.count)
        tableView.selectRowIndexes(all.subtracting(tableView.selectedRowIndexes), byExtendingSelection: false)
    }

    func focus() { view.window?.makeFirstResponder(tableView) }

    func refreshAppearance() {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<NSMaxRange(visible)),
                             columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    func setSortIndicator(_ key: SortKey, ascending: Bool) {
        updatingSort = true
        tableView.sortDescriptors = [NSSortDescriptor(key: key.rawValue, ascending: ascending)]
        updatingSort = false
    }

    func setSearchRoot(_ root: URL?) {
        searchRoot = root
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Column.folder.rawValue))?.isHidden = root == nil
    }

    func beginRename(_ url: URL) {
        guard let row = items.firstIndex(where: { $0.url.isSameFile(as: url) }) else { return }
        let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(Column.name.rawValue))
        guard column >= 0 else { return }
        tableView.selectRowIndexes([row], byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        guard let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        renamingItem = items[row]
        renamingField = field
        renameCancelled = false
        field.isEditable = true
        field.delegate = self
        view.window?.makeFirstResponder(field)
        RenameEditing.selectBaseName(in: field)
    }

    // MARK: Rename editing

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            renameCancelled = true
            view.window?.makeFirstResponder(tableView)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === renamingField,
              let item = renamingItem else { return }
        field.isEditable = false
        field.isSelectable = false
        field.delegate = nil
        renamingItem = nil
        renamingField = nil
        let original = item.displayName(showExtension: host?.showExtensions ?? true)
        let newName = field.stringValue
        if renameCancelled || newName == original || newName.isEmpty {
            field.stringValue = original
        } else {
            host?.fileView(self, rename: item, to: newName)
        }
        renameCancelled = false
        host?.fileViewDidEndRenaming(self)
        DispatchQueue.main.async { [weak self] in self?.focus() }
    }

    // MARK: Actions

    @objc private func doubleClicked() {
        guard tableView.clickedRow >= 0, let host else { return }
        host.fileView(self, open: selectedItems)
    }

    // MARK: Data source

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !updatingSort, let descriptor = tableView.sortDescriptors.first,
              let key = SortKey(rawValue: descriptor.key ?? "") else { return }
        host?.fileView(self, sortBy: key, ascending: descriptor.ascending)
    }

    func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
        guard tableColumn?.identifier.rawValue == Column.name.rawValue else { return nil }
        return items[safe: row]?.name
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        items[safe: row]?.url as NSURL?
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let host else { return [] }
        let urls = DragSupport.fileURLs(from: info)
        guard !urls.isEmpty else { return [] }
        if dropOperation == .on, let item = items[safe: row], item.isFolder,
           !urls.contains(where: { $0.isSameFile(as: item.url) }) {
            return host.fileView(self, dropOperationFor: urls, into: item.url, info: info)
        }
        tableView.setDropRow(-1, dropOperation: .on)
        return host.fileView(self, dropOperationFor: urls, into: host.currentFolder, info: info)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let host else { return false }
        let urls = DragSupport.fileURLs(from: info)
        var destination = host.currentFolder
        if row >= 0, dropOperation == .on, let item = items[safe: row], item.isFolder {
            destination = item.url
        }
        let operation = host.fileView(self, dropOperationFor: urls, into: destination, info: info)
        guard !operation.isEmpty else { return false }
        return host.fileView(self, acceptDrop: urls, into: destination, operation: operation)
    }

    // MARK: Delegate

    func tableViewSelectionDidChange(_ notification: Notification) {
        host?.fileViewSelectionDidChange(self)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let item = items[safe: row],
              let column = Column(rawValue: tableColumn.identifier.rawValue) else { return nil }
        let cell = makeCell(for: column, in: tableView)
        let dimmed = host?.isCut(item.url) ?? false
        cell.alphaValue = (dimmed || item.isHidden) ? 0.5 : 1
        switch column {
        case .name:
            cell.textField?.stringValue = item.displayName(showExtension: host?.showExtensions ?? true)
            (cell as? NameCellView)?.dots.colors = item.tags.map { Tags.color(for: $0) }
            cell.imageView?.image = IconProvider.icon(for: item.url)
            cell.toolTip = item.url.path
        case .folder:
            let parent = item.url.deletingLastPathComponent().path
            cell.textField?.stringValue = (parent as NSString).abbreviatingWithTildeInPath
            cell.toolTip = parent
        case .dateModified:
            cell.textField?.stringValue = item.modified.map { Formatters.date.string(from: $0) } ?? ""
        case .type:
            cell.textField?.stringValue = item.kind
        case .size:
            cell.textField?.stringValue = item.isFolder ? "" : Formatters.size(item.size)
        }
        return cell
    }

    private func makeCell(for column: Column, in tableView: NSTableView) -> NSTableCellView {
        let id = NSUserInterfaceItemIdentifier("cell." + column.rawValue)
        if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            return reused
        }
        let cell: NSTableCellView = column == .name ? NameCellView() : NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingTail
        text.font = .systemFont(ofSize: 13)
        text.cell?.usesSingleLineMode = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        cell.addSubview(text)
        cell.textField = text

        if column == .name, let nameCell = cell as? NameCellView {
            let dots = nameCell.dots
            dots.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(dots)
            text.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.imageScaling = .scaleProportionallyUpOrDown
            cell.addSubview(image)
            cell.imageView = image
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18),
                image.heightAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                dots.leadingAnchor.constraint(equalTo: text.trailingAnchor, constant: 4),
                dots.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
                dots.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                dots.heightAnchor.constraint(equalToConstant: 12),
            ])
        } else {
            text.textColor = .secondaryLabelColor
            text.alignment = column == .size ? .right : .left
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }
}
