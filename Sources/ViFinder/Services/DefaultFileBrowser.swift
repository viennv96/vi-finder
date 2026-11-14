import AppKit
import UniformTypeIdentifiers

/// Makes ViFinder the default app for folders (and the "file viewer" used by "Show in Finder"
/// in apps that respect the global NSFileViewer preference). macOS never lets an app replace
/// Finder completely — Desktop, Dock and Trash stay with Finder.
enum DefaultFileBrowser {
    static let finderURL = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
    private static let fileViewerKey = "NSFileViewer" as CFString

    /// Only possible when running from the .app bundle (not `swift run`).
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static var isDefault: Bool {
        guard let id = Bundle.main.bundleIdentifier,
              let handler = NSWorkspace.shared.urlForApplication(toOpen: .folder),
              let handlerID = Bundle(url: handler)?.bundleIdentifier else { return false }
        return handlerID == id
    }

    static func makeDefault(completion: @escaping (Error?) -> Void) {
        guard isAvailable, let id = Bundle.main.bundleIdentifier else { return }
        setFileViewer(id as CFString)
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: .folder) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    static func restoreFinder(completion: @escaping (Error?) -> Void) {
        setFileViewer(nil)
        NSWorkspace.shared.setDefaultApplication(at: finderURL, toOpen: .folder) { error in
            DispatchQueue.main.async { completion(error) }
        }
    }

    /// True when the global NSFileViewer points at ViFinder.
    static var isFileViewer: Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let value = CFPreferencesCopyValue(fileViewerKey, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        return value == id
    }

    /// "Show in Finder" must always reach the real Finder, even when ViFinder is the NSFileViewer
    /// (otherwise the request would bounce back to ViFinder).
    static func revealInFinder(_ urls: [URL]) {
        guard isFileViewer else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
            return
        }
        var targets: [URL] = []
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let target = isDir.boolValue && !NSWorkspace.shared.isFilePackage(atPath: url.path)
                ? url : url.deletingLastPathComponent()
            if !targets.contains(target) { targets.append(target) }
        }
        NSWorkspace.shared.open(targets, withApplicationAt: finderURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Same as `defaults write -g NSFileViewer <id>` / `defaults delete -g NSFileViewer`.
    private static func setFileViewer(_ value: CFString?) {
        CFPreferencesSetValue(fileViewerKey, value, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}
