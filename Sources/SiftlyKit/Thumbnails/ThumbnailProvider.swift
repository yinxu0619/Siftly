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

    /// In-flight preview loads, so concurrent requests/prefetches for the same
    /// file are coalesced instead of decoding the (slow) RAW twice.
    private var previewTasks: [URL: Task<NSImage?, Never>] = [:]

    public init(service: ThumbnailService) {
        self.service = service
        cache.countLimit = 600
        // Bound by approximate decoded byte cost (~256 MB) so memory stays low
        // even while scrolling through thousands of thumbnails.
        cache.totalCostLimit = 256 * 1024 * 1024
        previewCache.countLimit = 12
        // Bound preview memory regardless of how many neighbors are prefetched.
        previewCache.totalCostLimit = 512 * 1024 * 1024
    }

    /// Sizes the preview cache so prefetched neighbors aren't evicted before use.
    /// `count` is the per-side prefetch count chosen by the user.
    public func configurePreviewCache(count: Int) {
        previewCache.countLimit = max(12, count * 2 + 4)
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

    /// Large image for the full-size preview viewer. Concurrent callers for the
    /// same URL share one decode; results are cached so navigation is instant.
    public func previewImage(for url: URL, pixelSize: CGSize) async -> NSImage? {
        if let cached = previewCache.object(forKey: url as NSURL) {
            return cached
        }
        if let existing = previewTasks[url] {
            return await existing.value
        }

        let key = url as NSURL
        let task = Task<NSImage?, Never> { [service] in
            guard let cgImage = await service.thumbnail(for: url, size: pixelSize) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        previewTasks[url] = task
        let image = await task.value
        previewTasks[url] = nil

        if let image {
            let cost = Int(image.size.width * image.size.height) * 4
            previewCache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    /// Warms the preview cache for the given URLs in the background (used to
    /// preload the photos adjacent to the one currently being viewed).
    public func prefetchPreviews(_ urls: [URL], pixelSize: CGSize) {
        for url in urls {
            if previewCache.object(forKey: url as NSURL) != nil { continue }
            if previewTasks[url] != nil { continue }
            Task(priority: .utility) { [weak self] in
                _ = await self?.previewImage(for: url, pixelSize: pixelSize)
            }
        }
    }
}
