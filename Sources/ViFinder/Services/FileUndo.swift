import AppKit

/// Undo / redo for file operations (⌘Z / ⇧⌘Z, Ctrl+Z / Ctrl+Y), like Explorer.
///
/// Every operation is expressed with three reversible primitives:
/// - moves (rename, cut/paste, drag-move): move back / move again
/// - created items (new folder, copy, zip…): undo = move to Trash, redo = put back from Trash
/// - trashed items (Delete): undo = put back from Trash, redo = move to Trash again
/// Permanent deletes can't be undone (same as Windows).
enum FileUndo {
    /// Target object for UndoManager (must outlive tabs/windows).
    private final class Target: NSObject {}
    private static let target = Target()

    /// Original location → current location inside the Trash.
    private final class TrashMap {
        var map: [URL: URL]
        init(_ map: [URL: URL]) { self.map = map }
    }

    static func registerMoves(_ pairs: [(from: URL, to: URL)], name: String, in manager: UndoManager?) {
        guard !pairs.isEmpty else { return }
        register(name, in: manager,
                 undo: { try move(pairs.map { ($0.to, $0.from) }) },
                 redo: { try move(pairs) })
    }

    static func registerCreated(_ urls: [URL], name: String, in manager: UndoManager?) {
        guard !urls.isEmpty else { return }
        let trash = TrashMap([:])
        register(name, in: manager,
                 undo: { trash.map = try moveToTrash(urls) },
                 redo: { try putBack(trash.map) })
    }

    static func registerTrashed(_ map: [URL: URL], name: String, in manager: UndoManager?) {
        guard !map.isEmpty else { return }
        let trash = TrashMap(map)
        register(name, in: manager,
                 undo: { try putBack(trash.map) },
                 redo: { trash.map = try moveToTrash(Array(trash.map.keys)) })
    }

    // MARK: Private

    private static func register(_ name: String, in manager: UndoManager?,
                                 undo: @escaping () throws -> Void, redo: @escaping () throws -> Void) {
        guard let manager else { return }
        manager.registerUndo(withTarget: target) { _ in
            do { try undo() } catch { NSAlert(error: error).runModal() }
            // Registering while undoing puts the inverse on the redo stack (and vice versa).
            register(name, in: manager, undo: redo, redo: undo)
        }
        manager.setActionName(name)
    }

    private static func move(_ pairs: [(URL, URL)]) throws {
        for (from, to) in pairs {
            try FileManager.default.moveItem(at: from, to: to)
        }
    }

    private static func moveToTrash(_ urls: [URL]) throws -> [URL: URL] {
        var result: [URL: URL] = [:]
        for url in urls {
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            if let trashed { result[url] = trashed as URL }
        }
        return result
    }

    private static func putBack(_ map: [URL: URL]) throws {
        for (original, trashed) in map {
            try FileManager.default.moveItem(at: trashed, to: original)
        }
    }
}
