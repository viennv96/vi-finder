import AppKit

/// Windows 11 command bar: New ▾ | Cut Copy Paste Rename Share Delete | Sort ▾ View ▾ | ⋯
final class CommandBar: NSView {
    let newButton: NSButton
    let cutButton: NSButton
    let copyButton: NSButton
    let pasteButton: NSButton
    let renameButton: NSButton
    let shareButton: NSButton
    let deleteButton: NSButton
    let sortButton: NSButton
    let viewButton: NSButton
    let moreButton: NSButton
    let terminalButton: NSButton

    init(target: AnyObject) {
        func button(_ title: String?, _ symbol: String, _ action: Selector, tip: String, menu: Bool = false) -> NSButton {
            let b = NSButton()
            b.bezelStyle = .accessoryBarAction
            b.showsBorderOnlyWhileMouseInside = true
            b.image = NSImage.symbol(symbol, size: 15)
            b.imagePosition = title == nil ? .imageOnly : .imageLeading
            b.title = title.map { menu ? "\($0) ⌄" : $0 } ?? ""
            b.font = .systemFont(ofSize: 13)
            b.target = target
            b.action = action
            b.toolTip = tip
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 30).isActive = true
            if title == nil { b.widthAnchor.constraint(equalToConstant: 34).isActive = true }
            return b
        }
        typealias E = ExplorerViewController
        newButton = button("New", "plus.circle", #selector(E.showNewMenu(_:)), tip: "Create a new item", menu: true)
        cutButton = button(nil, "scissors", #selector(E.cut(_:)), tip: "Cut (⌘X)")
        copyButton = button(nil, "doc.on.doc", #selector(E.copy(_:)), tip: "Copy (⌘C)")
        pasteButton = button(nil, "doc.on.clipboard", #selector(E.paste(_:)), tip: "Paste (⌘V)")
        renameButton = button(nil, "character.cursor.ibeam", #selector(E.renameSelection(_:)), tip: "Rename (F2)")
        shareButton = button(nil, "square.and.arrow.up", #selector(E.shareSelection(_:)), tip: "Share")
        deleteButton = button(nil, "trash", #selector(E.moveToTrash(_:)), tip: "Delete (⌫ / Del)")
        sortButton = button("Sort", "arrow.up.arrow.down", #selector(E.showSortMenu(_:)), tip: "Sort items", menu: true)
        viewButton = button("View", "rectangle.grid.1x2", #selector(E.showViewMenu(_:)), tip: "Change the view", menu: true)
        terminalButton = button("Terminal", "terminal", #selector(E.openInTerminal(_:)), tip: "Open in Terminal (⌥⌘T)")
        moreButton = button(nil, "ellipsis", #selector(E.showMoreMenu(_:)), tip: "See more")
        super.init(frame: .zero)

        func separator() -> NSView {
            let v = NSBox()
            v.boxType = .separator
            v.translatesAutoresizingMaskIntoConstraints = false
            v.heightAnchor.constraint(equalToConstant: 20).isActive = true
            return v
        }
        let stack = NSStackView(views: [
            newButton, separator(),
            cutButton, copyButton, pasteButton, renameButton, shareButton, deleteButton, separator(),
            sortButton, viewButton, separator(),
            terminalButton, moreButton,
        ])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.setHuggingPriority(.defaultHigh, for: .horizontal)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 40),
        ])
        stack.setVisibilityPriority(.detachOnlyIfNecessary, for: terminalButton)
        stack.setVisibilityPriority(.detachOnlyIfNecessary, for: shareButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(hasSelection: Bool, canPaste: Bool, canWrite: Bool) {
        cutButton.isEnabled = hasSelection && canWrite
        copyButton.isEnabled = hasSelection
        renameButton.isEnabled = hasSelection && canWrite
        shareButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection && canWrite
        pasteButton.isEnabled = canPaste && canWrite
        newButton.isEnabled = canWrite
    }
}

/// Bottom status bar: "12 items | 2 items selected 4.1 MB" … [progress] … [details][icons]
final class StatusBar: NSView {
    let label = NSTextField(labelWithString: "")
    let progressLabel = NSTextField(labelWithString: "")
    let spinner = NSProgressIndicator()
    let detailsButton = NSButton()
    let iconsButton = NSButton()

    init(target: AnyObject) {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        progressLabel.font = .systemFont(ofSize: 12)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.lineBreakMode = .byTruncatingMiddle
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        for (button, mode) in [(detailsButton, ViewMode.details), (iconsButton, ViewMode.largeIcons)] {
            button.bezelStyle = .accessoryBarAction
            button.setButtonType(.pushOnPushOff)
            button.image = NSImage.symbol(mode.symbol, size: 12)
            button.imagePosition = .imageOnly
            button.target = target
            button.action = #selector(ExplorerViewController.setViewModeFromStatusBar(_:))
            button.tag = mode == .details ? 0 : 1
            button.toolTip = mode == .details ? "Display information about each item in the window" : "Display items by using large thumbnails"
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [label, spacer, spinner, progressLabel, detailsButton, iconsButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 8)
        addSubview(stack)
        stack.pinEdges(to: self)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        progressLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setMode(_ mode: ViewMode) {
        detailsButton.state = mode == .details ? .on : .off
        iconsButton.state = mode == .details ? .off : .on
    }

    func setProgress(_ text: String?) {
        progressLabel.stringValue = text ?? ""
        if text == nil { spinner.stopAnimation(nil) } else { spinner.startAnimation(nil) }
    }
}
