import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Loads and caches thumbnails with a memory-bounded NSCache. Offscreen loads
/// are cancelled automatically: each grid item drives this from a SwiftUI
/// `.task` which is cancelled when the item leaves the lazy grid's render window.
@MainActor
public final class ThumbnailProvider: ObservableObject {
    private let service: ThumbnailService
    private let cache = NSCache<NSURL, NSImage>()
    /// Small separate cache for large preview images (keeps grid cache clean).
    private let previewCache = NSCache<NSURL, NSImage>()

    public init(service: ThumbnailService) {
        self.service = service
        cache.countLimit = 600
        // Bound by approximate decoded byte cost (~256 MB) so memory stays low
        // even while scrolling through thousands of thumbnails.
        cache.totalCostLimit = 256 * 1024 * 1024
        previewCache.countLimit = 8
    }

    public func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    public func image(for url: URL, size: CGSize) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if Task.isCancelled { return nil }

        guard let cgImage = await service.thumbnail(for: url, size: size) else {
            return nil
        }
        // If the requesting view scrolled away mid-load, skip publishing it but
        // still cache it (cheap) so a later revisit is instant.
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        let cost = cgImage.width * cgImage.height * 4
        cache.setObject(image, forKey: url as NSURL, cost: cost)
        return Task.isCancelled ? nil : image
    }

    /// Large image for the full-size preview viewer.
    public func previewImage(for url: URL, pixelSize: CGSize) async -> NSImage? {
        if let cached = previewCache.object(forKey: url as NSURL) {
            return cached
        }
        if Task.isCancelled { return nil }
        guard let cgImage = await service.thumbnail(for: url, size: pixelSize) else {
            return nil
        }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        previewCache.setObject(image, forKey: url as NSURL)
        return Task.isCancelled ? nil : image
    }
}
