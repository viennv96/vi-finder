import Foundation

enum ViewMode: String, CaseIterable {
    case largeIcons, mediumIcons, list, details, tiles, content

    /// Order used in menus (same as Windows Explorer's View menu).
    static let menuOrder: [ViewMode] = [.largeIcons, .mediumIcons, .list, .details, .tiles, .content]

    var title: String {
        switch self {
        case .largeIcons: return "Large icons"
        case .mediumIcons: return "Medium icons"
        case .list: return "List"
        case .details: return "Details"
        case .tiles: return "Tiles"
        case .content: return "Content"
        }
    }

    var symbol: String {
        switch self {
        case .largeIcons: return "square.grid.2x2"
        case .mediumIcons: return "square.grid.3x3"
        case .list: return "list.dash"
        case .details: return "list.bullet"
        case .tiles: return "rectangle.grid.2x2"
        case .content: return "list.bullet.rectangle"
        }
    }

    /// ⌘1…⌘6 (⌘1/⌘2/⌘3 kept from earlier versions).
    var shortcut: String {
        switch self {
        case .largeIcons: return "1"
        case .mediumIcons: return "2"
        case .details: return "3"
        case .list: return "4"
        case .tiles: return "5"
        case .content: return "6"
        }
    }
}

enum SortKey: String, CaseIterable {
    case name, dateModified, type, size

    var title: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date modified"
        case .type: return "Type"
        case .size: return "Size"
        }
    }
}

/// Global, persisted preferences (shared by all windows/tabs).
enum Prefs {
    private static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "showHidden": false,
            "showExtensions": true,
            "viewMode": ViewMode.details.rawValue,
            "sortKey": SortKey.name.rawValue,
            "sortAscending": true,
            "terminalBundleID": "com.apple.Terminal",
            "showNavigationPane": true,
            "showPreviewPane": false,
        ])
    }

    private static func changed() {
        NotificationCenter.default.post(name: .viPreferencesChanged, object: nil)
    }

    static var showHidden: Bool {
        get { d.bool(forKey: "showHidden") }
        set { d.set(newValue, forKey: "showHidden"); changed() }
    }

    static var showExtensions: Bool {
        get { d.bool(forKey: "showExtensions") }
        set { d.set(newValue, forKey: "showExtensions"); changed() }
    }

    static var showNavigationPane: Bool {
        get { d.bool(forKey: "showNavigationPane") }
        set { d.set(newValue, forKey: "showNavigationPane"); changed() }
    }

    static var showPreviewPane: Bool {
        get { d.bool(forKey: "showPreviewPane") }
        set { d.set(newValue, forKey: "showPreviewPane"); changed() }
    }

    /// Default view mode for new windows/tabs (each tab keeps its own afterwards).
    static var viewMode: ViewMode {
        get { ViewMode(rawValue: d.string(forKey: "viewMode") ?? "") ?? .details }
        set { d.set(newValue.rawValue, forKey: "viewMode") }
    }

    static var sortKey: SortKey {
        get { SortKey(rawValue: d.string(forKey: "sortKey") ?? "") ?? .name }
        set { d.set(newValue.rawValue, forKey: "sortKey") }
    }

    static var sortAscending: Bool {
        get { d.bool(forKey: "sortAscending") }
        set { d.set(newValue, forKey: "sortAscending") }
    }

    static var terminalBundleID: String {
        get { d.string(forKey: "terminalBundleID") ?? "com.apple.Terminal" }
        set { d.set(newValue, forKey: "terminalBundleID") }
    }
}
