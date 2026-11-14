import AppKit

struct ExternalApp {
    let name: String
    let bundleID: String

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { appURL != nil }
    var icon: NSImage? {
        guard let url = appURL else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

/// "Open in Terminal" — the macOS equivalent of Windows 11's right-click → Open in Terminal.
enum TerminalLauncher {
    static let terminals: [ExternalApp] = [
        ExternalApp(name: "Terminal", bundleID: "com.apple.Terminal"),
        ExternalApp(name: "iTerm", bundleID: "com.googlecode.iterm2"),
        ExternalApp(name: "Warp", bundleID: "dev.warp.Warp-Stable"),
        ExternalApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        ExternalApp(name: "WezTerm", bundleID: "com.github.wez.wezterm"),
    ]

    static let editors: [ExternalApp] = [
        ExternalApp(name: "Visual Studio Code", bundleID: "com.microsoft.VSCode"),
        ExternalApp(name: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"),
        ExternalApp(name: "Zed", bundleID: "dev.zed.Zed"),
    ]

    static var installedTerminals: [ExternalApp] { terminals.filter(\.isInstalled) }
    static var installedEditors: [ExternalApp] { editors.filter(\.isInstalled) }

    static var preferred: ExternalApp {
        let id = Prefs.terminalBundleID
        return installedTerminals.first { $0.bundleID == id } ?? terminals[0]
    }

    /// Opens `folder` in the given terminal (or the preferred one).
    static func open(_ folder: URL, with app: ExternalApp? = nil) {
        let app = app ?? preferred
        guard let appURL = app.appURL else {
            NSSound.beep()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: config) { _, error in
            if let error {
                DispatchQueue.main.async {
                    let alert = NSAlert(error: error)
                    alert.messageText = "Could not open \(app.name)"
                    alert.runModal()
                }
            }
        }
    }
}
