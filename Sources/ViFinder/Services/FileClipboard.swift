import AppKit

/// Cut / Copy / Paste of files through the system pasteboard, so it interoperates with Finder
/// and other apps. "Cut" is marked with a private pasteboard type.
final class FileClipboard {
    static let shared = FileClipboard()

    private let cutType = NSPasteboard.PasteboardType("com.vifinder.cut")
    private var pb: NSPasteboard { .general }
    private var cachedChangeCount = -1
    private var cachedCut: Set<String> = []

    enum Operation { case copy, cut }

    func write(_ urls: [URL], operation: Operation) {
        guard !urls.isEmpty else { return }
        pb.clearContents()
        let items: [NSPasteboardItem] = urls.enumerated().map { index, url in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            if index == 0 {
                item.setString(url.path, forType: .string)
                if operation == .cut { item.setString("1", forType: cutType) }
            }
            return item
        }
        pb.writeObjects(items)
        notify()
    }

    /// Plain text copy (e.g. "Copy as path").
    func writeText(_ text: String) {
        pb.clearContents()
        pb.setString(text, forType: .string)
        notify()
    }

    func read() -> (urls: [URL], operation: Operation)? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self],
                                        options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return nil }
        let isCut = pb.pasteboardItems?.first?.types.contains(cutType) ?? false
        return (urls, isCut ? .cut : .copy)
    }

    var hasFiles: Bool {
        pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    /// Paths currently "cut" (shown dimmed in the file list, like Windows).
    var cutPaths: Set<String> {
        if pb.changeCount != cachedChangeCount {
            cachedChangeCount = pb.changeCount
            if let content = read(), content.operation == .cut {
                cachedCut = Set(content.urls.map { $0.standardizedFileURL.path })
            } else {
                cachedCut = []
            }
        }
        return cachedCut
    }

    /// After a cut has been pasted, the clipboard is emptied (Windows behaviour).
    func clearAfterCutPaste() {
        pb.clearContents()
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: .viClipboardChanged, object: nil)
    }
}
