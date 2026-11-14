import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Caches file icons and Quick Look thumbnails (for the icon views, like Windows thumbnails).
enum IconProvider {
    private static let iconCache = NSCache<NSString, NSImage>()
    private static let thumbCache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        if let tag = url.tagName { return Tags.dot(Tags.color(for: tag), size: 16) }
        let key = url.path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache.setObject(image, forKey: key)
        return image
    }

    static func cachedThumbnail(for url: URL, size: CGFloat) -> NSImage? {
        thumbCache.object(forKey: "\(url.path)#\(Int(size))" as NSString)
    }

    /// Asynchronously produces a thumbnail; `completion` runs on main only if a thumbnail exists.
    /// Like Windows: real previews only for pictures, videos and PDFs; everything else keeps its icon
    /// (Quick Look thumbnails of short text files are nearly blank white pages).
    static func wantsThumbnail(_ item: FileItem) -> Bool {
        guard !item.isFolder, !item.isPackage,
              let type = UTType(filenameExtension: item.pathExtension) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf)
    }

    static func thumbnail(for item: FileItem, size: CGFloat, completion: @escaping (NSImage) -> Void) {
        guard wantsThumbnail(item) else { return }
        let key = "\(item.url.path)#\(Int(size))" as NSString
        if let cached = thumbCache.object(forKey: key) {
            completion(cached)
            return
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url, size: CGSize(width: size, height: size),
            scale: scale, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async {
                thumbCache.setObject(image, forKey: key)
                completion(image)
            }
        }
    }

    static func invalidate(_ url: URL) {
        iconCache.removeObject(forKey: url.path as NSString)
    }
}
