import AppKit

/// Windows 11-style tab strip drawn inside the (transparent) title bar, next to the traffic lights.
final class TabStripView: NSView {
    static let height: CGFloat = 38
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNew: (() -> Void)?
    var onMenu: ((Int) -> NSMenu?)?

    private var tabViews: [TabItemView] = []
    private let addButton = NSButton()
    private let leadingInset: CGFloat = 80

    override init(frame: NSRect) {
        super.init(frame: frame)
        addButton.bezelStyle = .accessoryBarAction
        addButton.showsBorderOnlyWhileMouseInside = true
        addButton.image = NSImage.symbol("plus", size: 13, weight: .medium)
        addButton.imagePosition = .imageOnly
        addButton.target = self
        addButton.action = #selector(addClicked)
        addButton.toolTip = "New tab (⌘T)"
        addSubview(addButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    func setTabs(_ tabs: [(title: String, icon: NSImage, tooltip: String)], selected: Int) {
        while tabViews.count < tabs.count {
            let view = TabItemView()
            view.strip = self
            addSubview(view)
            tabViews.append(view)
        }
        while tabViews.count > tabs.count {
            tabViews.removeLast().removeFromSuperview()
        }
        for (index, tab) in tabs.enumerated() {
            let view = tabViews[index]
            view.index = index
            view.title = tab.title
            view.icon = tab.icon
            view.toolTip = tab.tooltip
            view.isSelected = index == selected
        }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let addWidth: CGFloat = 30
        let available = bounds.width - leadingInset - addWidth - 16
        let count = CGFloat(max(tabViews.count, 1))
        let width = max(min(available / count, 240), 72)
        var x = leadingInset
        let top: CGFloat = 6
        for view in tabViews {
            view.frame = NSRect(x: x, y: top, width: width, height: bounds.height - top)
            x += width
        }
        addButton.frame = NSRect(x: x + 4, y: top + (bounds.height - top - 26) / 2, width: addWidth, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        TabStripView.stripColor(for: effectiveAppearance).setFill()
        bounds.fill()
    }

    static func stripColor(for appearance: NSAppearance) -> NSColor {
        var color = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            color = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB)?
                .blended(withFraction: dark ? 0.35 : 0.07, of: .black) ?? .windowBackgroundColor
        }
        return color
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    @objc private func addClicked() { onNew?() }

    fileprivate func tabClicked(_ index: Int) { onSelect?(index) }
    fileprivate func tabClosed(_ index: Int) { onClose?(index) }
    fileprivate func tabMenu(_ index: Int) -> NSMenu? { onMenu?(index) }
}

private final class TabItemView: NSView {
    weak var strip: TabStripView?
    var index = 0
    var title = "" { didSet { label.stringValue = title } }
    var icon: NSImage? { didSet { iconView.image = icon } }
    var isSelected = false { didSet { updateLook() } }
    private var hovering = false { didSet { updateLook() } }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        closeButton.bezelStyle = .accessoryBarAction
        closeButton.showsBorderOnlyWhileMouseInside = true
        closeButton.image = NSImage.symbol("xmark", size: 9, weight: .semibold)
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close tab (⌘W)"
        addSubview(iconView)
        addSubview(label)
        addSubview(closeButton)
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The whole tab is clickable (icon/label included); only the × button keeps its own clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit.isDescendant(of: closeButton) ? hit : self
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        iconView.frame = NSRect(x: 10, y: (h - 16) / 2, width: 16, height: 16)
        closeButton.frame = NSRect(x: bounds.width - 26, y: (h - 20) / 2, width: 20, height: 20)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: 32, y: (h - labelHeight) / 2, width: max(bounds.width - 32 - 30, 10), height: labelHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        strip?.tabClicked(index)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { strip?.tabClosed(index) } // middle-click closes
    }

    override func menu(for event: NSEvent) -> NSMenu? { strip?.tabMenu(index) }

    @objc private func closeClicked() { strip?.tabClosed(index) }

    private func updateLook() {
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 0)
        if isSelected {
            // Selected tab merges into the navigation row below (rounded top corners only).
            let path = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + 8),
                                    xRadius: 7, yRadius: 7)
            NSColor.windowBackgroundColor.setFill()
            path.fill()
        } else if hovering {
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 3), xRadius: 6, yRadius: 6)
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            path.fill()
        } else if let strip, index + 1 < strip.subviews.count {
            // Thin divider between unselected tabs, like Windows 11.
            NSColor.separatorColor.setFill()
            NSRect(x: bounds.maxX - 1, y: 10, width: 1, height: bounds.height - 18).fill()
        }
    }
}

/// Window content: the tab strip on top, the active tab's Explorer below.
final class TabsContainerViewController: NSViewController {
    let strip = TabStripView()
    private let host = NSView()
    private weak var shown: NSViewController?

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 720))
        strip.translatesAutoresizingMaskIntoConstraints = false
        host.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(strip)
        root.addSubview(host)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.topAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: TabStripView.height),
            host.topAnchor.constraint(equalTo: strip.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            host.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }

    func show(_ controller: NSViewController) {
        guard controller !== shown else { return }
        shown?.view.removeFromSuperview()
        if controller.parent !== self { addChild(controller) }
        host.addSubview(controller.view)
        controller.view.pinEdges(to: host)
        shown = controller
    }

    func remove(_ controller: NSViewController) {
        if shown === controller {
            controller.view.removeFromSuperview()
            shown = nil
        }
        controller.removeFromParent()
    }
}
