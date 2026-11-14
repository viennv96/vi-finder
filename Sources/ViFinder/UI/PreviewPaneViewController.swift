import AppKit
import Quartz

/// Windows "Preview pane" (Alt+P): Quick Look preview of the selected file on the right.
final class PreviewPaneViewController: NSViewController {
    private var previewView: QLPreviewView?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private var infoStack: NSStackView!
    private var shownURL: URL?
    private var pending: DispatchWorkItem?

    override func loadView() {
        let root = NSView()
        if let ql = QLPreviewView(frame: .zero, style: .normal) {
            ql.autostarts = true
            ql.translatesAutoresizingMaskIntoConstraints = false
            ql.isHidden = true
            root.addSubview(ql)
            ql.pinEdges(to: root)
            previewView = ql
        }

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 96).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 96).isActive = true
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.alignment = .center
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        infoStack = NSStackView(views: [iconView, titleLabel, detailLabel])
        infoStack.orientation = .vertical
        infoStack.alignment = .centerX
        infoStack.spacing = 8
        infoStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(infoStack)
        NSLayoutConstraint.activate([
            infoStack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            infoStack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -30),
            infoStack.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -32),
        ])
        view = root
        showInfo(icon: nil, title: "", detail: "Select a file to preview.")
    }

    /// Debounced so fast keyboard navigation doesn't spin up a preview for every row.
    func show(_ items: [FileItem]) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.update(items) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func update(_ items: [FileItem]) {
        if items.count == 1, !items[0].isFolder, let ql = previewView {
            let item = items[0]
            if shownURL != item.url {
                shownURL = item.url
                ql.previewItem = item.url as NSURL
            }
            ql.isHidden = false
            infoStack.isHidden = true
            return
        }
        shownURL = nil
        previewView?.previewItem = nil
        previewView?.isHidden = true
        switch items.count {
        case 0:
            showInfo(icon: nil, title: "", detail: "Select a file to preview.")
        case 1:
            showInfo(icon: IconProvider.icon(for: items[0].url), title: items[0].name, detail: items[0].kind)
        default:
            let bytes = items.filter { !$0.isFolder }.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
            let size = bytes > 0 ? "\n" + Formatters.size(bytes) : ""
            showInfo(icon: NSImage.symbol("doc.on.doc", size: 48), title: "\(items.count) items selected", detail: size)
        }
    }

    private func showInfo(icon: NSImage?, title: String, detail: String) {
        infoStack.isHidden = false
        iconView.image = icon
        iconView.isHidden = icon == nil
        titleLabel.stringValue = title
        titleLabel.isHidden = title.isEmpty
        detailLabel.stringValue = detail.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
