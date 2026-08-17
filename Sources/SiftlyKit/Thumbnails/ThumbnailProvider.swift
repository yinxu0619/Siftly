import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Caps how many image decodes run at once. The card reader — not the CPU — is
/// the bottleneck when culling: a LazyVGrid can easily kick off 50 concurrent
/// RAW decodes, which thrashes the reader and makes *everything* slower.
///
/// Waiters are served **LIFO**. When the user flings the grid past a thousand
/// rows, the cells now on screen are the newest requests; FIFO would put them
/// behind every request issued during the fling, so the visible screen would
/// fill only after the whole backlog drained.
private actor DecodeGate {
    private let limit: Int
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    private func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeLast().resume()   // newest request first
        }
    }

    /// Runs `work` while holding a slot. `work` must not throw, so the slot is
    /// always handed back.
    func withSlot<T>(_ work: () async -> T) async -> T {
        await acquire()
        let result = await work()
        release()
        return result
    }
}

/// Loads and caches thumbnails with a memory-bounded NSCache.
///
/// Decodes are shared between concurrent callers for the same image, queued
/// behind a concurrency gate, and dropped if every caller that asked for them
/// has gone away (the grid cell scrolled off, the viewer moved on).
@MainActor
public final class ThumbnailProvider: ObservableObject {
    private let service: ThumbnailService
    private let cache = NSCache<NSString, NSImage>()
    /// Small separate cache for large preview images (keeps grid cache clean).
    private let previewCache = NSCache<NSString, NSImage>()

    /// In-flight loads, so concurrent requests (fast scrolling, prefetches)
    /// for the same file are coalesced instead of decoding the slow RAW twice.
    private var tasks: [String: Task<NSImage?, Never>] = [:]

    /// Live callers per key, one ticket each. A queued decode that reaches the
    /// front with an empty ticket set has no one left to deliver to and is
    /// skipped — this is what keeps a fling from costing a thousand decodes.
    /// Tickets are a `Set` so releasing twice (cancellation *and* normal
    /// return) is harmless.
    private var tickets: [String: Set<UUID>] = [:]

    private let gridGate = DecodeGate(limit: 6)
    private let previewGate = DecodeGate(limit: 2)
    /// Speculative neighbor loads get their own single slot, so they can never
    /// delay the photo the user actually navigated to — which is the entire
    /// point of the prefetch setting.
    private let prefetchGate = DecodeGate(limit: 1)

    /// Thumbnail sizes in **points**. `ThumbnailService` applies the Retina
    /// scale itself, so these must not be pre-multiplied — doing so decoded at
    /// 4x the pixels actually needed.
    nonisolated private static let sizeBuckets: [CGFloat] = [128, 192, 256, 384, 512]

    /// The bucket used to serve a request for a cell `points` wide. The size
    /// slider is continuous, but decoding at every intermediate size would blow
    /// up the cache and re-decode on every slider tick; snapping means dragging
    /// the slider is free until it crosses a bucket boundary.
    nonisolated public static func bucket(forPoints points: CGFloat) -> CGFloat {
        sizeBuckets.first { $0 >= points } ?? sizeBuckets[sizeBuckets.count - 1]
    }

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

    // MARK: - Keys

    private static func gridKey(_ url: URL, bucket: CGFloat) -> String {
        "grid\(Int(bucket))|\(url.absoluteString)"
    }

    private static func previewKey(_ url: URL) -> String {
        "preview|\(url.absoluteString)"
    }

    // MARK: - Cache reads

    public func cachedImage(for url: URL, bucket: CGFloat) -> NSImage? {
        cache.object(forKey: Self.gridKey(url, bucket: bucket) as NSString)
    }

    /// Best already-decoded representation of `url` at any size — used to show
    /// something instantly while a larger version decodes.
    public func anyCachedImage(for url: URL) -> NSImage? {
        for bucket in Self.sizeBuckets.reversed() {
            if let image = cache.object(forKey: Self.gridKey(url, bucket: bucket) as NSString) {
                return image
            }
        }
        return nil
    }

    // MARK: - Interest tracking

    private func takeTicket(_ key: String) -> UUID {
        let ticket = UUID()
        tickets[key, default: []].insert(ticket)
        return ticket
    }

    private func dropTicket(_ key: String, _ ticket: UUID) {
        guard var live = tickets[key] else { return }
        live.remove(ticket)
        if live.isEmpty { tickets[key] = nil } else { tickets[key] = live }
    }

    private func isWanted(_ key: String) -> Bool {
        !(tickets[key]?.isEmpty ?? true)
    }

    // MARK: - Loading

    /// Shared body for grid and preview loads: coalesce, queue, decode, cache.
    private func load(
        key: String,
        cache targetCache: NSCache<NSString, NSImage>,
        gate: DecodeGate,
        decode: @escaping @Sendable () async -> CGImage?
    ) async -> NSImage? {
        if let cached = targetCache.object(forKey: key as NSString) { return cached }
        if Task.isCancelled { return nil }

        let ticket = takeTicket(key)
        defer { dropTicket(key, ticket) }

        let task: Task<NSImage?, Never>
        if let existing = tasks[key] {
            task = existing
        } else {
            let wanted: @Sendable () async -> Bool = { [weak self] in
                guard let provider = self else { return false }
                return await provider.isWanted(key)
            }
            task = Task.detached(priority: .userInitiated) {
                await gate.withSlot {
                    // Everyone who asked for this has moved on while we queued.
                    guard await wanted() else { return nil }
                    guard let cgImage = await decode() else { return nil }
                    return NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                }
            }
            tasks[key] = task
        }

        // `await task.value` on a non-throwing Task isn't itself cancellable, so
        // surrender the ticket eagerly on cancellation: that lets the queued
        // decode see it has no audience and return immediately.
        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { @MainActor [weak self] in self?.dropTicket(key, ticket) }
        }

        // Only clear the slot if it still holds *our* task. A later caller may
        // already have installed a fresh one (the decode returned nil and was
        // not cached), and clobbering it would cause a duplicate decode.
        if tasks[key] == task { tasks[key] = nil }

        if let image {
            let cost = Int(image.size.width * image.size.height) * 4
            targetCache.setObject(image, forKey: key as NSString, cost: cost)
        }
        return image
    }

    /// Grid thumbnail at the given point bucket. Concurrent callers for the same
    /// (url, bucket) share one decode.
    public func image(for url: URL, bucket: CGFloat) async -> NSImage? {
        let size = CGSize(width: bucket, height: bucket)
        let image = await load(
            key: Self.gridKey(url, bucket: bucket),
            cache: cache,
            gate: gridGate,
            decode: { [service] in await service.thumbnail(for: url, size: size) }
        )
        // Cached above even when the requesting cell scrolled away (a later
        // revisit is then instant), but don't hand it to a cancelled caller.
        return Task.isCancelled ? nil : image
    }

    /// Large image for the full-size preview viewer. `prefetch` routes the load
    /// to the background lane so it can't hold up an interactive request.
    public func previewImage(
        for url: URL,
        pixelSize: CGSize,
        prefetch: Bool = false
    ) async -> NSImage? {
        await load(
            key: Self.previewKey(url),
            cache: previewCache,
            gate: prefetch ? prefetchGate : previewGate,
            decode: { [service] in await service.thumbnail(for: url, size: pixelSize) }
        )
    }

    /// Warms the preview cache for the given URLs in the background (used to
    /// preload the photos adjacent to the one currently being viewed).
    public func prefetchPreviews(_ urls: [URL], pixelSize: CGSize) {
        for url in urls {
            let key = Self.previewKey(url)
            if previewCache.object(forKey: key as NSString) != nil { continue }
            if tasks[key] != nil { continue }
            Task(priority: .utility) { [weak self] in
                _ = await self?.previewImage(for: url, pixelSize: pixelSize, prefetch: true)
            }
        }
    }
}
