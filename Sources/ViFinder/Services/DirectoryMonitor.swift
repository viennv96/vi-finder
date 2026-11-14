import Foundation

/// Watches a single directory for changes (files added/removed/renamed) using kqueue.
final class DirectoryMonitor {
    private var source: DispatchSourceFileSystemObject?
    var onChange: (() -> Void)?

    func start(_ url: URL) {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: .main)
        src.setEventHandler { [weak self] in self?.onChange?() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
