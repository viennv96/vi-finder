import AppKit

/// Collection view that forwards keys, double-clicks and context menus.
final class FileCollectionView: NSCollectionView {
    var keyHandler: ((NSEvent) -> Bool)?
    var menuProvider: ((IndexPath?) -> NSMenu?)?
    var doubleClickHandler: ((IndexPath) -> Void)?
    /// Start point of Shift range selection (last item clicked without Shift), like Windows.
    var selectionAnchor: IndexPath?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
        if !event.modifierFlags.contains(.shift), selectionIndexPaths.count == 1 {
            selectionAnchor = selectionIndexPaths.first
        }
    }

    override func mouseDown(with event: NSEvent) {
        let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        let flags = event.modifierFlags

        // Shift+click: select everything between the anchor and the clicked item.
        // Shift+⌘+click adds that range to the current selection.
        if flags.contains(.shift), let indexPath,
           let anchor = selectionAnchor ?? selectionIndexPaths.min() {
            window?.makeFirstResponder(self)
            let range = min(anchor.item, indexPath.item)...max(anchor.item, indexPath.item)
            let rangePaths = Set(range.map { IndexPath(item: $0, section: 0) })
            let target = flags.contains(.command) ? selectionIndexPaths.union(rangePaths) : rangePaths
            deselectItems(at: selectionIndexPaths.subtracting(target))
            selectItems(at: target.subtracting(selectionIndexPaths), scrollPosition: [])
            selectionAnchor = anchor
            delegate?.collectionView?(self, didSelectItemsAt: target)
            return
        }

        super.mouseDown(with: event)
        selectionAnchor = indexPath
        if event.clickCount == 2, let indexPath {
            doubleClickHandler?(indexPath)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let indexPath = indexPathForItem(at: convert(event.locationInWindow, from: nil))
        if let indexPath {
            if !selectionIndexPaths.contains(indexPath) {
                deselectAll(nil)
                selectItems(at: [indexPath], scrollPosition: [])
                delegate?.collectionView?(self, didSelectItemsAt: [indexPath])
            }
        } else {
            deselectAll(nil)
            delegate?.collectionView?(self, didDeselectItemsAt: [])
        }
        return menuProvider?(indexPath)
    }
}

/// One tile: icon/thumbnail above a (max 2 lines) name.
final class IconItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("IconItem")
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var iconSize: NSLayoutConstraint!
    var representedURL: URL?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 4
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor.clear.cgColor

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: 12)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping   // wrap to two lines like Windows, then truncate
        label.cell?.truncatesLastVisibleLine = true
        root.addSubview(icon)
        root.addSubview(label)
        iconSize = icon.heightAnchor.constraint(equalToConstant: 64)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            icon.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            iconSize,
            icon.widthAnchor.constraint(equalTo: icon.heightAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -4),
        ])
        view = root
        imageView = icon
        textField = label
    }

    func configure(_ item: FileItem, name: String, iconPoints: CGFloat, dimmed: Bool) {
        representedURL = item.url
        iconSize.constant = iconPoints
        label.stringValue = name
        view.toolTip = item.url.path
        view.alphaValue = (dimmed || item.isHidden) ? 0.5 : 1
        icon.image = (IconProvider.wantsThumbnail(item) ? IconProvider.cachedThumbnail(for: item.url, size: iconPoints) : nil)
            ?? IconProvider.icon(for: item.url)
        IconProvider.thumbnail(for: item, size: iconPoints) { [weak self] image in
            guard let self, self.representedURL == item.url else { return }
            self.icon.image = image
        }
        updateSelection()
    }

    override var isSelected: Bool { didSet { updateSelection() } }
    override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateSelection() } }

    private func updateSelection() {
        let selected = isSelected || highlightState == .forSelection
        let accent = NSColor.controlAccentColor
        view.layer?.backgroundColor = selected ? accent.withAlphaComponent(0.22).cgColor : NSColor.clear.cgColor
        view.layer?.borderColor = selected ? accent.withAlphaComponent(0.6).cgColor : NSColor.clear.cgColor
    }
}

/// Windows "Large icons" / "Medium icons" views.
final class IconsViewController: NSViewController, FileView, NSCollectionViewDataSource,
                                 NSCollectionViewDelegate, NSTextFieldDelegate {
    weak var host: FileViewHost?
    private(set) var items: [FileItem] = []
    private let collectionView = FileCollectionView()
    private let layout = NSCollectionViewFlowLayout()
    private var iconPoints: CGFloat = 64

    private var renamingItem: FileItem?
    private weak var renamingField: NSTextField?
    private var renameCancelled = false
    var isRenaming: Bool { renamingItem != nil }

    var mode: ViewMode = .largeIcons {
        didSet { applyMode() }
    }

    var selectedItems: [FileItem] {
        collectionView.selectionIndexPaths.map(\.item).sorted().compactMap { items[safe: $0] }
    }

    override func loadView() {
        layout.minimumInteritemSpacing = 6
        layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.textBackgroundColor]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(IconItem.self, forItemWithIdentifier: IconItem.id)
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.copy, .move, .link], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.keyHandler = { [weak self] event in
            guard let self, let host = self.host else { return false }
            return host.fileView(self, handleKey: event)
        }
        collectionView.menuProvider = { [weak self] indexPath in
            guard let self, let host = self.host else { return nil }
            return host.fileView(self, menuFor: indexPath.flatMap { self.items[safe: $0.item] })
        }
        collectionView.doubleClickHandler = { [weak self] _ in
            guard let self, let host = self.host else { return }
            host.fileView(self, open: self.selectedItems)
        }

        let scroll = NSScrollView()
        scroll.documentView = collectionView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        view = scroll
        applyMode()
    }

    private func applyMode() {
        switch mode {
        case .mediumIcons:
            iconPoints = 48
            layout.itemSize = NSSize(width: 92, height: 92)
        default:
            iconPoints = 80
            layout.itemSize = NSSize(width: 118, height: 124)
        }
        layout.invalidateLayout()
        collectionView.reloadData()
    }

    // MARK: FileView

    func display(_ items: [FileItem], selecting: Set<URL>, scrollToTop: Bool) {
        self.items = items
        collectionView.reloadData()
        select(selecting)
        if selecting.isEmpty && scrollToTop { collectionView.scroll(.zero) }
    }

    func select(_ urls: Set<URL>) {
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        let indexPaths = Set(items.indices.filter { paths.contains(items[$0].url.path) }
            .map { IndexPath(item: $0, section: 0) })
        collectionView.deselectAll(nil)
        collectionView.selectItems(at: indexPaths, scrollPosition: indexPaths.isEmpty ? [] : .nearestHorizontalEdge)
        collectionView.selectionAnchor = indexPaths.min()
        if let first = indexPaths.min() { collectionView.scrollToItems(at: [first], scrollPosition: .nearestHorizontalEdge) }
        host?.fileViewSelectionDidChange(self)
    }

    func selectAll() {
        collectionView.selectAll(nil)
        host?.fileViewSelectionDidChange(self)
    }

    func selectNone() {
        collectionView.deselectAll(nil)
        host?.fileViewSelectionDidChange(self)
    }

    func invertSelection() {
        let all = Set(items.indices.map { IndexPath(item: $0, section: 0) })
        let inverted = all.subtracting(collectionView.selectionIndexPaths)
        collectionView.deselectAll(nil)
        collectionView.selectItems(at: inverted, scrollPosition: [])
        host?.fileViewSelectionDidChange(self)
    }

    func focus() { view.window?.makeFirstResponder(collectionView) }

    func refreshAppearance() {
        let visible = collectionView.indexPathsForVisibleItems()
        collectionView.reloadItems(at: visible)
    }

    func setSortIndicator(_ key: SortKey, ascending: Bool) {}

    func beginRename(_ url: URL) {
        guard let index = items.firstIndex(where: { $0.url.isSameFile(as: url) }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        select([url])
        collectionView.layoutSubtreeIfNeeded()
        guard let tile = collectionView.item(at: indexPath), let field = tile.textField else { return }
        renamingItem = items[index]
        renamingField = field
        renameCancelled = false
        field.isEditable = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.delegate = self
        view.window?.makeFirstResponder(field)
        RenameEditing.selectBaseName(in: field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            renameCancelled = true
            view.window?.makeFirstResponder(collectionView)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            view.window?.makeFirstResponder(collectionView)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === renamingField,
              let item = renamingItem else { return }
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
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

    // MARK: Data source / delegate

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let tile = collectionView.makeItem(withIdentifier: IconItem.id, for: indexPath)
        if let tile = tile as? IconItem, let item = items[safe: indexPath.item] {
            tile.configure(item, name: item.displayName(showExtension: host?.showExtensions ?? true),
                           iconPoints: iconPoints, dimmed: host?.isCut(item.url) ?? false)
        }
        return tile
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        host?.fileViewSelectionDidChange(self)
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        host?.fileViewSelectionDidChange(self)
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        items[safe: indexPath.item]?.url as NSURL?
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo,
                        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard let host else { return [] }
        let urls = DragSupport.fileURLs(from: info)
        guard !urls.isEmpty else { return [] }
        let index = proposedIndexPath.pointee.item
        if dropOperation.pointee == .on, let item = items[safe: index], item.isFolder,
           !urls.contains(where: { $0.isSameFile(as: item.url) }) {
            return host.fileView(self, dropOperationFor: urls, into: item.url, info: info)
        }
        // Drop into the current folder: target the end of the list ("between" mode).
        dropOperation.pointee = .before
        proposedIndexPath.pointee = NSIndexPath(forItem: items.count, inSection: 0)
        return host.fileView(self, dropOperationFor: urls, into: host.currentFolder, info: info)
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo,
                        indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let host else { return false }
        let urls = DragSupport.fileURLs(from: info)
        var destination = host.currentFolder
        if dropOperation == .on, let item = items[safe: indexPath.item], item.isFolder {
            destination = item.url
        }
        let operation = host.fileView(self, dropOperationFor: urls, into: destination, info: info)
        guard !operation.isEmpty else { return false }
        return host.fileView(self, acceptDrop: urls, into: destination, operation: operation)
    }
}
