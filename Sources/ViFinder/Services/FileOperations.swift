import AppKit

/// File system operations with Windows-like naming rules.
enum FileOps {
    struct Step {
        let source: URL
        let destination: URL
        let replaceExisting: Bool
    }

    enum ConflictChoice { case replace, skip, keepBoth }

    enum OpError: LocalizedError {
        case intoItself(String)
        case invalidName
        case alreadyExists(String)

        var errorDescription: String? {
            switch self {
            case .intoItself(let name):
                return "The destination folder is a subfolder of the source folder (\(name))."
            case .invalidName:
                return "A file name can't contain any of the following characters: / :"
            case .alreadyExists(let name):
                return "There is already a file with the same name (\(name)) in this location."
            }
        }
    }

    private static let fm = FileManager.default
    private static let workQueue = DispatchQueue(label: "vifinder.fileops", qos: .userInitiated)

    // MARK: Naming

    /// "name.ext" → first free of "name.ext", "name (2).ext", ... (or "name - Copy.ext" style).
    static func uniqueURL(for name: String, in folder: URL, copySuffix: Bool = false) -> URL {
        var isDir: ObjCBool = false
        let existing = folder.appendingPathComponent(name)
        let isFolder = fm.fileExists(atPath: existing.path, isDirectory: &isDir) && isDir.boolValue
            && !NSWorkspace.shared.isFilePackage(atPath: existing.path)
        let base = isFolder ? name : (name as NSString).deletingPathExtension
        let ext = isFolder ? "" : (name as NSString).pathExtension
        func make(_ stem: String) -> URL {
            folder.appendingPathComponent(ext.isEmpty ? stem : "\(stem).\(ext)")
        }
        let first = copySuffix ? make("\(base) - Copy") : make(base)
        if !fm.fileExists(atPath: first.path) { return first }
        var n = 2
        while true {
            let candidate = copySuffix ? make("\(base) - Copy (\(n))") : make("\(base) (\(n))")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !name.contains("/") && !name.contains(":") && name != "." && name != ".."
    }

    // MARK: Create / rename / delete

    static func createFolder(in folder: URL) throws -> URL {
        let url = uniqueURL(for: "New folder", in: folder)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    static func createTextFile(in folder: URL) throws -> URL {
        let url = uniqueURL(for: "New Text Document.txt", in: folder)
        guard fm.createFile(atPath: url.path, contents: Data()) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }

    static func rename(_ url: URL, to newName: String) throws -> URL {
        guard isValidName(newName) else { throw OpError.invalidName }
        let destination = url.deletingLastPathComponent().appendingPathComponent(newName)
        if destination.isSameFile(as: url) { return url }
        // Allow case-only renames on case-insensitive volumes.
        let caseOnly = destination.path.lowercased() == url.path.lowercased()
        if fm.fileExists(atPath: destination.path) && !caseOnly {
            throw OpError.alreadyExists(newName)
        }
        try fm.moveItem(at: url, to: destination)
        return destination
    }

    static func moveToTrash(_ urls: [URL], completion: @escaping ([Error]) -> Void) {
        NSWorkspace.shared.recycle(urls) { _, error in
            DispatchQueue.main.async { completion(error.map { [$0] } ?? []) }
        }
    }

    static func deletePermanently(_ urls: [URL], completion: @escaping ([Error]) -> Void) {
        workQueue.async {
            var errors: [Error] = []
            for url in urls {
                do { try fm.removeItem(at: url) } catch { errors.append(error) }
            }
            DispatchQueue.main.async { completion(errors) }
        }
    }

    // MARK: Copy / move

    /// Builds the list of steps for pasting/dropping `sources` into `folder`.
    /// `resolve` is asked once (with the number of conflicts) when names collide.
    static func planTransfer(_ sources: [URL], into folder: URL, move: Bool,
                             resolve: (Int) -> ConflictChoice?) throws -> [Step]? {
        var plain: [Step] = []
        var conflicts: [(URL, URL)] = []
        for src in sources {
            if folder.isDescendant(of: src) { throw OpError.intoItself(src.lastPathComponent) }
            let dst = folder.appendingPathComponent(src.lastPathComponent)
            if dst.isSameFile(as: src) {
                // Same folder: copy becomes "name - Copy", move is a no-op.
                if !move {
                    plain.append(Step(source: src, destination: uniqueURL(for: src.lastPathComponent, in: folder, copySuffix: true), replaceExisting: false))
                }
                continue
            }
            if fm.fileExists(atPath: dst.path) {
                conflicts.append((src, dst))
            } else {
                plain.append(Step(source: src, destination: dst, replaceExisting: false))
            }
        }
        guard !conflicts.isEmpty else { return plain }
        guard let choice = resolve(conflicts.count) else { return nil } // cancelled
        for (src, dst) in conflicts {
            switch choice {
            case .replace:
                plain.append(Step(source: src, destination: dst, replaceExisting: true))
            case .skip:
                break
            case .keepBoth:
                plain.append(Step(source: src, destination: uniqueURL(for: src.lastPathComponent, in: folder), replaceExisting: false))
            }
        }
        return plain
    }

    /// Runs the steps in the background. `progress(done, total, name)` and `completion` are called on main.
    static func execute(_ steps: [Step], move: Bool,
                        progress: @escaping (Int, Int, String) -> Void,
                        completion: @escaping (_ created: [URL], _ errors: [Error]) -> Void) {
        workQueue.async {
            var created: [URL] = []
            var errors: [Error] = []
            for (index, step) in steps.enumerated() {
                let name = step.source.lastPathComponent
                DispatchQueue.main.async { progress(index, steps.count, name) }
                do {
                    if step.replaceExisting && fm.fileExists(atPath: step.destination.path) {
                        try fm.trashItem(at: step.destination, resultingItemURL: nil)
                    }
                    if move {
                        try fm.moveItem(at: step.source, to: step.destination)
                    } else {
                        try fm.copyItem(at: step.source, to: step.destination)
                    }
                    created.append(step.destination)
                } catch {
                    errors.append(error)
                }
            }
            DispatchQueue.main.async { completion(created, errors) }
        }
    }

    // MARK: Zip

    /// "Compress to ZIP file" — single item → item.zip, multiple → Archive.zip.
    static func compress(_ urls: [URL], in folder: URL, completion: @escaping (URL?, Error?) -> Void) {
        guard let first = urls.first else { return }
        let zipName = urls.count == 1 ? "\((first.lastPathComponent as NSString).deletingPathExtension).zip" : "Archive.zip"
        let output = uniqueURL(for: zipName, in: folder)
        let process = Process()
        if urls.count == 1 {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, output.path]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = folder
            process.arguments = ["-r", "-q", "-y", output.lastPathComponent] + urls.map(\.lastPathComponent)
        }
        run(process) { error in completion(error == nil ? output : nil, error) }
    }

    /// "Extract All" — extracts into a folder named after the archive.
    static func extract(_ zip: URL, completion: @escaping (URL?, Error?) -> Void) {
        let folder = zip.deletingLastPathComponent()
        let target = uniqueURL(for: (zip.lastPathComponent as NSString).deletingPathExtension, in: folder)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, target.path]
        run(process) { error in completion(error == nil ? target : nil, error) }
    }

    private static func run(_ process: Process, completion: @escaping (Error?) -> Void) {
        workQueue.async {
            do {
                try process.run()
                process.waitUntilExit()
                let error: Error? = process.terminationStatus == 0 ? nil :
                    NSError(domain: "ViFinder", code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "The operation failed (exit code \(process.terminationStatus))."])
                DispatchQueue.main.async { completion(error) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }
}
