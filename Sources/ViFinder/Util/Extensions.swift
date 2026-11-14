import AppKit

extension NSImage {
    /// SF Symbol helper.
    static func symbol(_ name: String, size: CGFloat = 15, weight: NSFont.Weight = .regular) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension URL {
    /// Normalised file URL used for comparisons (no trailing slash, symlinks of /private resolved lazily).
    var normalized: URL { standardizedFileURL.resolvingSymlinksInPath() }

    var isRoot: Bool { standardizedFileURL.path == "/" }

    func isSameFile(as other: URL) -> Bool {
        standardizedFileURL.path == other.standardizedFileURL.path
    }

    /// True if `self` is `ancestor` or is located somewhere below it.
    func isDescendant(of ancestor: URL) -> Bool {
        let me = standardizedFileURL.path
        let base = ancestor.standardizedFileURL.path
        if me == base { return true }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return me.hasPrefix(prefix)
    }

    var volumeIdentifier: NSObject? {
        (try? resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }

    /// Display name as the system shows it (localized folder names, volume names...).
    var displayName: String {
        if isRoot {
            return (try? resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName ?? "Macintosh HD"
        }
        return FileManager.default.displayName(atPath: path)
    }
}

enum Formatters {
    static let size: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f
    }()

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .medium
        return f
    }()

    static func size(_ bytes: Int64?) -> String {
        guard let bytes else { return "" }
        if bytes == 0 { return "0 KB" }
        // Windows-style: anything below 1 KB still shows as "1 KB"
        if bytes > 0 && bytes < 1024 { return "1 KB" }
        return size.string(fromByteCount: bytes)
    }

    static func itemCount(_ n: Int) -> String {
        n == 1 ? "1 item" : "\(n) items"
    }
}

extension NSView {
    func pinEdges(to other: NSView, insets: NSEdgeInsets = .init()) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

extension NSView {
    /// Shows `menu` right below this view (used by the command bar / breadcrumb buttons).
    func popUpBelow(_ menu: NSMenu) {
        let y = isFlipped ? bounds.maxY + 2 : bounds.minY - 2
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: y), in: self)
    }
}

extension NSMenu {
    @discardableResult
    func addItem(_ title: String, _ action: Selector?, target: AnyObject?, key: String = "",
                 modifiers: NSEvent.ModifierFlags = [.command], symbol: String? = nil,
                 represented: Any? = nil, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        if !key.isEmpty { item.keyEquivalentModifierMask = modifiers }
        if let symbol { item.image = NSImage.symbol(symbol, size: 13) }
        item.representedObject = represented
        item.tag = tag
        addItem(item)
        return item
    }

    func addSeparator() { addItem(.separator()) }
}

extension Notification.Name {
    static let viPreferencesChanged = Notification.Name("ViFinder.preferencesChanged")
    static let viClipboardChanged = Notification.Name("ViFinder.clipboardChanged")
}

/// Function key strings for menu key equivalents.
enum FunctionKey {
    static let f2 = String(UnicodeScalar(NSF2FunctionKey)!)
    static let f5 = String(UnicodeScalar(NSF5FunctionKey)!)
    static let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    static let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
    static let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    static let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
    static let backspace = String(UnicodeScalar(NSBackspaceCharacter)!)
    static let forwardDelete = String(UnicodeScalar(NSDeleteFunctionKey)!)
}

enum KeyCode {
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let backspace: UInt16 = 51
    static let escape: UInt16 = 53
    static let forwardDelete: UInt16 = 117
    static let f2: UInt16 = 120
    static let f5: UInt16 = 96
    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    static let d: UInt16 = 2
    static let l: UInt16 = 37
}
