import Foundation
import SystemConfiguration

/// Well-known locations (home, Desktop, Documents…, computer name).
///
/// Set `VIFINDER_DEMO_HOME=/some/folder` to run against a fake home folder — used to take the
/// README screenshots without exposing personal folders, account names or drives.
enum Places {
    static let demoHome: URL? = ProcessInfo.processInfo.environment["VIFINDER_DEMO_HOME"]
        .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }

    static var isDemo: Bool { demoHome != nil }

    static var home: URL { demoHome ?? FileManager.default.homeDirectoryForCurrentUser }

    static func user(_ directory: FileManager.SearchPathDirectory) -> URL {
        if let demoHome {
            let names: [FileManager.SearchPathDirectory: String] = [
                .desktopDirectory: "Desktop", .documentDirectory: "Documents", .downloadsDirectory: "Downloads",
                .picturesDirectory: "Pictures", .musicDirectory: "Music", .moviesDirectory: "Movies",
            ]
            return demoHome.appendingPathComponent(names[directory] ?? "")
        }
        return FileManager.default.urls(for: directory, in: .userDomainMask).first ?? home
    }

    static var computerName: String {
        if isDemo { return "MacBook Pro" }
        return (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "This Mac"
    }

    static var iCloudDrive: URL { home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs") }
    static var cloudStorage: URL { home.appendingPathComponent("Library/CloudStorage") }

    static func mountedVolumes() -> [URL] {
        if isDemo { return [URL(fileURLWithPath: "/")] }
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeLocalizedNameKey],
                                                     options: [.skipHiddenVolumes]) ?? [URL(fileURLWithPath: "/")]
    }
}
