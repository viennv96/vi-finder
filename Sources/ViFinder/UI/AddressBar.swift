import AppKit

/// Windows-style address bar.
/// Breadcrumb mode: `[icon] Macintosh HD › Users › me › Documents ›` — click a segment to go there,
/// click a `›` to pick one of its sub-folders. Click the empty area (or ⌘L) to type a path.
final class AddressBar: NSView, NSTextFieldDelegate {
    /// Text typed by the user and confirmed with Return.
    var onSubmit: ((String) -> Void)?
    var onNavigate: ((URL) -> Void)?

    private(set) var url = URL(fileURLWithPath: NSHomeDirectory())
    private let iconView = NSImageView()
    private let crumbs = FlippedView()
    private let field = NSTextField()
    private let overflow = NSButton()
    private var segments: [(title: String, url: URL)] = []
    private var segmentButtons: [NSButton] = []
    private var chevronButtons: [NSButton] = []
    private var hiddenCount = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        crumbs.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.isHidden = true

        overflow.isBordered = false
        overflow.image = NSImage.symbol("chevron.left.2", size: 10)
        overflow.target = self
        overflow.action = #selector(showOverflow(_:))
        overflow.toolTip = "Previous locations"
        crumbs.addSubview(overflow)

        addSubview(iconView)
        addSubview(crumbs)
        addSubview(field)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            crumbs.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            crumbs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            crumbs.topAnchor.constraint(equalTo: topAnchor),
            crumbs.bottomAnchor.constraint(equalTo: bottomAnchor),
            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30),
        ])
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = (isEditing ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        }
    }

    var isEditing: Bool { !field.isHidden }

    // MARK: Public

    func setURL(_ url: URL) {
        self.url = url
        iconView.image = IconProvider.icon(for: url)
        segments = AddressBar.segments(for: url)
        rebuildCrumbs()
        if isEditing { field.stringValue = url.path }
    }

    func beginEditing() {
        field.stringValue = url.path
        field.isHidden = false
        crumbs.isHidden = true
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        updateColors()
    }

    func endEditing() {
        field.isHidden = true
        crumbs.isHidden = false
        updateColors()
    }

    // MARK: Segments

    static func segments(for url: URL) -> [(title: String, url: URL)] {
        var chain: [URL] = []
        var current = url.standardizedFileURL
        while true {
            chain.insert(current, at: 0)
            if current.isRoot { break }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path { break }
            current = parent
        }
        // External volumes: start the breadcrumb at the volume ("/Volumes/USB" → "USB").
        if chain.count >= 3, chain[1].path == "/Volumes" {
            chain.removeFirst(2)
        }
        return chain.map { ($0.displayName, $0) }
    }

    private func rebuildCrumbs() {
        (segmentButtons + chevronButtons).forEach { $0.removeFromSuperview() }
        segmentButtons = []
        chevronButtons = []
        for (index, segment) in segments.enumerated() {
            let button = NSButton(title: segment.title, target: self, action: #selector(segmentClicked(_:)))
            button.bezelStyle = .accessoryBarAction
            button.showsBorderOnlyWhileMouseInside = true
            button.font = .systemFont(ofSize: 13)
            button.tag = index
            button.lineBreakMode = .byTruncatingTail
            crumbs.addSubview(button)
            segmentButtons.append(button)

            let chevron = NSButton(image: NSImage.symbol("chevron.right", size: 9, weight: .semibold)!,
                                   target: self, action: #selector(chevronClicked(_:)))
            chevron.bezelStyle = .accessoryBarAction
            chevron.showsBorderOnlyWhileMouseInside = true
            chevron.tag = index
            chevron.contentTintColor = .secondaryLabelColor
            crumbs.addSubview(chevron)
            chevronButtons.append(chevron)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutCrumbs()
    }

    private func layoutCrumbs() {
        let available = crumbs.bounds.width
        let height = crumbs.bounds.height
        let widths = segments.indices.map { i -> CGFloat in
            min(segmentButtons[i].intrinsicContentSize.width, 220) + chevronButtons[i].intrinsicContentSize.width
        }
        let overflowWidth: CGFloat = 22
        var total = widths.reduce(0, +)
        var hidden = 0
        while total + (hidden > 0 ? overflowWidth : 0) > available && hidden < segments.count - 1 {
            total -= widths[hidden]
            hidden += 1
        }
        hiddenCount = hidden
        var x: CGFloat = 0
        overflow.isHidden = hidden == 0
        if hidden > 0 {
            overflow.frame = NSRect(x: 0, y: (height - 20) / 2, width: overflowWidth, height: 20)
            x = overflowWidth
        }
        for i in segments.indices {
            let isHidden = i < hidden
            segmentButtons[i].isHidden = isHidden
            chevronButtons[i].isHidden = isHidden
            guard !isHidden else { continue }
            let w = min(segmentButtons[i].intrinsicContentSize.width, 220)
            let remaining = max(available - x - chevronButtons[i].intrinsicContentSize.width, 30)
            let bw = min(w, remaining)
            segmentButtons[i].frame = NSRect(x: x, y: (height - 24) / 2, width: bw, height: 24)
            x += bw
            let cw = chevronButtons[i].intrinsicContentSize.width
            chevronButtons[i].frame = NSRect(x: x, y: (height - 24) / 2, width: cw, height: 24)
            x += cw
        }
    }

    @objc private func segmentClicked(_ sender: NSButton) {
        guard let segment = segments[safe: sender.tag] else { return }
        onNavigate?(segment.url)
    }

    @objc private func chevronClicked(_ sender: NSButton) {
        guard let segment = segments[safe: sender.tag] else { return }
        let menu = NSMenu()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var options: FileManager.DirectoryEnumerationOptions = []
        if !Prefs.showHidden { options.insert(.skipsHiddenFiles) }
        let folders = ((try? FileManager.default.contentsOfDirectory(at: segment.url, includingPropertiesForKeys: keys,
                                                                     options: options)) ?? [])
            .filter {
                let v = try? $0.resourceValues(forKeys: Set(keys))
                return (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let next = segments[safe: sender.tag + 1]?.url
        for folder in folders.prefix(300) {
            let item = menu.addItem(folder.displayName, #selector(menuNavigate(_:)), target: self, represented: folder)
            let icon = IconProvider.icon(for: folder).copy() as! NSImage
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            if let next, next.isSameFile(as: folder) { item.state = .on }
        }
        if folders.isEmpty {
            let empty = NSMenuItem(title: "No sub-folders", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        sender.popUpBelow(menu)
    }

    @objc private func showOverflow(_ sender: NSButton) {
        let menu = NSMenu()
        for segment in segments.prefix(hiddenCount).reversed() {
            menu.addItem(segment.title, #selector(menuNavigate(_:)), target: self, represented: segment.url)
        }
        sender.popUpBelow(menu)
    }

    @objc private func menuNavigate(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { onNavigate?(url) }
    }

    // MARK: Editing

    override func mouseDown(with event: NSEvent) {
        if !isEditing { beginEditing() } else { super.mouseDown(with: event) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            let text = field.stringValue
            endEditing()
            onSubmit?(text)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing()
    }

    // Path auto-completion (Esc / F5 / ⌥Esc shows the list), completes the last path component.
    func control(_ control: NSControl, textView: NSTextView, completions words: [String],
                 forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        let text = textView.string as NSString
        let partial = text.substring(with: charRange)
        let before = text.substring(to: charRange.location)
        let dir = (before as NSString).expandingTildeInPath
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.isEmpty ? "/" : dir) else { return [] }
        return names.filter { $0.lowercased().hasPrefix(partial.lowercased()) && (Prefs.showHidden || !$0.hasPrefix(".")) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(50).map { $0 }
    }
}

/// Top-left origin container used for manual breadcrumb layout.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
