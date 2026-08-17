import XCTest
import CoreGraphics
@testable import SiftlyKit

#if os(macOS)

/// Records every decode it is asked to perform, and takes long enough that
/// requests genuinely queue behind the concurrency gate.
private final class FakeThumbnailService: ThumbnailService, @unchecked Sendable {
    private let lock = NSLock()
    private var _decoded: [URL] = []
    private let delayNanos: UInt64

    init(delayMilliseconds: UInt64 = 50) {
        self.delayNanos = delayMilliseconds * 1_000_000
    }

    var decoded: [URL] {
        lock.lock(); defer { lock.unlock() }
        return _decoded
    }

    func thumbnail(for url: URL, size: CGSize) async -> CGImage? {
        try? await Task.sleep(nanoseconds: delayNanos)
        lock.lock(); _decoded.append(url); lock.unlock()
        return Self.onePixel()
    }

    private static func onePixel() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}

@MainActor
final class ThumbnailProviderTests: XCTestCase {
    private func urls(_ n: Int) -> [URL] {
        (0..<n).map { URL(fileURLWithPath: "/tmp/siftly-test/DSC\($0).ARW") }
    }

    /// The regression this guards: with the decode moved onto an unstructured
    /// task, cancelling a grid cell's `.task` no longer reached the decode, so
    /// flinging past a thousand rows still decoded all thousand — and the cells
    /// actually on screen queued behind them.
    func testCancelledRequestsAreNotDecoded() async {
        let service = FakeThumbnailService(delayMilliseconds: 50)
        let provider = ThumbnailProvider(service: service)
        let files = urls(40)

        let requests = files.map { url in
            Task { _ = await provider.image(for: url, bucket: 128) }
        }
        // Let every request get past its entry check and actually queue on the
        // gate — cancelling sooner would be caught by the cheap `Task.isCancelled`
        // guard and would not exercise the queue at all.
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(service.decoded.count, 0, "decodes should still be in flight")

        // Everyone scrolled away before their turn came up.
        requests.forEach { $0.cancel() }
        for request in requests { _ = await request.value }

        // Only decodes already past the gate when cancellation landed may run;
        // the gate's width bounds that. Without interest tracking this is 40.
        let count = service.decoded.count
        XCTAssertLessThanOrEqual(count, 6, "queued decodes should be dropped, got \(count)/40")
    }

    /// Concurrent callers for the same image share one decode. Without this, a
    /// scroll back and forth re-decodes the same RAW repeatedly.
    func testConcurrentRequestsForTheSameImageShareOneDecode() async {
        let service = FakeThumbnailService(delayMilliseconds: 20)
        let provider = ThumbnailProvider(service: service)
        let url = urls(1)[0]

        async let a = provider.image(for: url, bucket: 128)
        async let b = provider.image(for: url, bucket: 128)
        async let c = provider.image(for: url, bucket: 128)
        let results = await [a, b, c]

        XCTAssertEqual(service.decoded.count, 1)
        XCTAssertEqual(results.compactMap { $0 }.count, 3)
    }

    /// A second request at the same bucket is served from cache; a different
    /// bucket is a genuinely different image and must decode again.
    func testCacheIsKeyedByBucket() async {
        let service = FakeThumbnailService(delayMilliseconds: 1)
        let provider = ThumbnailProvider(service: service)
        let url = urls(1)[0]

        _ = await provider.image(for: url, bucket: 128)
        _ = await provider.image(for: url, bucket: 128)
        XCTAssertEqual(service.decoded.count, 1, "same bucket should hit the cache")

        _ = await provider.image(for: url, bucket: 256)
        XCTAssertEqual(service.decoded.count, 2, "a larger bucket needs its own decode")

        XCTAssertNotNil(provider.cachedImage(for: url, bucket: 128))
        XCTAssertNotNil(provider.anyCachedImage(for: url))
    }
}
#endif
