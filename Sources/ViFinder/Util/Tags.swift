import AppKit

/// Finder tags (stored in the file system, so they stay in sync with Finder).
enum Tags {
    /// Virtual location for "all files with tag X": `vifinder-tag:///Red`.
    static let scheme = "vifinder-tag"

    static func location(for tag: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.path = "/" + tag
        return components.url!
    }

    /// Finder's standard colour tags, in Finder's menu order (names are localized by macOS).
    static var standard: [(name: String, color: NSColor)] {
        let labels = NSWorkspace.shared.fileLabels
        let colors = NSWorkspace.shared.fileLabelColors
        // NSWorkspace order: None, Gray, Green, Purple, Blue, Yellow, Red, Orange
        return [6, 7, 5, 2, 4, 3, 1].compactMap { index in
            index < labels.count && index < colors.count ? (labels[index], colors[index]) : nil
        }
    }

    static func color(for tag: String) -> NSColor? {
        standard.first { $0.name == tag }?.color
    }

    static func dot(_ color: NSColor?, size: CGFloat = 12) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            if let color {
                color.setFill()
                path.fill()
            } else {
                NSColor.secondaryLabelColor.setStroke()
                path.lineWidth = 1.2
                path.stroke()
            }
            return true
        }
    }

    static func setTags(_ tags: [String], for url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
    }
}

extension URL {
    var isTagLocation: Bool { scheme == Tags.scheme }
    var tagName: String? { isTagLocation ? String(path.dropFirst()) : nil }
}

/// Draws a file's tag colours as small overlapping dots (Details view, next to the name).
final class TagDotsView: NSView {
    var colors: [NSColor?] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: colors.isEmpty ? 0 : CGFloat(colors.count) * 7 + 5, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, color) in colors.enumerated() {
            let rect = NSRect(x: CGFloat(index) * 7, y: (bounds.height - 11) / 2, width: 11, height: 11)
            let path = NSBezierPath(ovalIn: rect)
            (color ?? .systemGray).setFill()
            path.fill()
            NSColor.textBackgroundColor.setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }
    }
}
