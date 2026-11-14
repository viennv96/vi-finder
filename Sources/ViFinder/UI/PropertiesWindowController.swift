import AppKit

/// Windows-like "Properties" dialog (General tab).
final class PropertiesWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [PropertiesWindowController] = []
    private let urls: [URL]
    private let sizeLabel = NSTextField(labelWithString: "Calculating…")
    private let containsLabel = NSTextField(labelWithString: "")
    private var cancelled = false

    static func show(for urls: [URL]) {
        let controller = PropertiesWindowController(urls: urls)
        open.append(controller)
        controller.showWindow(nil)
        controller.window?.center()
    }

    init(urls: [URL]) {
        self.urls = urls
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.delegate = self
        panel.title = urls.count == 1 ? "\(urls[0].displayName) Properties" : "\(urls.count) items Properties"
        build()
        computeSize()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        cancelled = true
        PropertiesWindowController.open.removeAll { $0 === self }
    }

    private func build() {
        guard let content = window?.contentView else { return }
        let icon = NSImageView(image: urls.count == 1 ? IconProvider.icon(for: urls[0]) : NSImage.symbol("doc.on.doc", size: 32)!)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let name = NSTextField(labelWithString: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items")
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.isSelectable = true
        name.lineBreakMode = .byTruncatingMiddle

        var rows: [[NSView]] = []
        func label(_ s: String) -> NSTextField {
            let l = NSTextField(labelWithString: s)
            l.textColor = .secondaryLabelColor
            return l
        }
        func value(_ s: String) -> NSTextField {
            let v = NSTextField(wrappingLabelWithString: s)
            v.isSelectable = true
            v.preferredMaxLayoutWidth = 290
            return v
        }
        let first = urls[0]
        let values = try? first.resourceValues(forKeys: [.localizedTypeDescriptionKey, .creationDateKey,
                                                         .contentModificationDateKey, .contentAccessDateKey,
                                                         .isDirectoryKey, .isHiddenKey, .isWritableKey])
        if urls.count == 1 {
            rows.append([label("Type:"), value(values?.localizedTypeDescription ?? "File")])
            if values?.isDirectory != true || NSWorkspace.shared.isFilePackage(atPath: first.path) {
                let app = NSWorkspace.shared.urlForApplication(toOpen: first)
                rows.append([label("Opens with:"), value(app.map { FileManager.default.displayName(atPath: $0.path) } ?? "—")])
            }
        } else {
            rows.append([label("Type:"), value("Multiple types")])
        }
        rows.append([label("Location:"), value(first.deletingLastPathComponent().path)])
        rows.append([label("Size:"), sizeLabel])
        rows.append([label("Contains:"), containsLabel])
        if urls.count == 1 {
            let df = Formatters.longDate
            rows.append([label("Created:"), value(values?.creationDate.map(df.string) ?? "—")])
            rows.append([label("Modified:"), value(values?.contentModificationDate.map(df.string) ?? "—")])
            rows.append([label("Accessed:"), value(values?.contentAccessDate.map(df.string) ?? "—")])
            var attrs: [String] = []
            if values?.isWritable == false { attrs.append("Read-only") }
            if values?.isHidden == true { attrs.append("Hidden") }
            rows.append([label("Attributes:"), value(attrs.isEmpty ? "—" : attrs.joined(separator: ", "))])
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing

        let header = NSStackView(views: [icon, name])
        header.spacing = 12
        let ok = NSButton(title: "OK", target: self, action: #selector(closeWindow))
        ok.keyEquivalent = "\r"
        let stack = NSStackView(views: [header, NSBox.separator(), grid, ok])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.setCustomSpacing(18, after: grid)
        content.addSubview(stack)
        stack.pinEdges(to: content)
        ok.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20).isActive = true
        stack.arrangedSubviews[1].widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
    }

    @objc private func closeWindow() { window?.close() }

    private func computeSize() {
        let urls = self.urls
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var bytes: Int64 = 0
            var files = 0
            var folders = 0
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey]
            var lastUpdate = Date()
            for url in urls {
                let v = try? url.resourceValues(forKeys: keys)
                if v?.isDirectory == true {
                    guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { continue }
                    for case let child as URL in e {
                        if self?.cancelled ?? true { return }
                        let cv = try? child.resourceValues(forKeys: keys)
                        if cv?.isDirectory == true { folders += 1 } else {
                            files += 1
                            bytes += Int64(cv?.fileSize ?? 0)
                        }
                        if Date().timeIntervalSince(lastUpdate) > 0.3 {
                            lastUpdate = Date()
                            let (b, f, d) = (bytes, files, folders)
                            DispatchQueue.main.async { self?.show(bytes: b, files: f, folders: d, done: false) }
                        }
                    }
                } else {
                    files += 1
                    bytes += Int64(v?.fileSize ?? 0)
                }
            }
            let (b, f, d) = (bytes, files, folders)
            DispatchQueue.main.async { self?.show(bytes: b, files: f, folders: d, done: true) }
        }
    }

    private func show(bytes: Int64, files: Int, folders: Int, done: Bool) {
        let exact = NumberFormatter.localizedString(from: NSNumber(value: bytes), number: .decimal)
        sizeLabel.stringValue = "\(Formatters.size(bytes)) (\(exact) bytes)" + (done ? "" : " …")
        containsLabel.stringValue = "\(files) Files, \(folders) Folders"
    }
}

extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
