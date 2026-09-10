import XCTest
import CoreImage
@testable import SiftlyKit

final class FileSafetyRegressionTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("siftly-audit-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: dir) }

    func testDifferentContentSameSizeMustNotBeSkipped() throws {
        let source = dir.appendingPathComponent("card/DSC001.ARW")
        let destination = dir.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4096).write(to: source)
        let existing = destination.appendingPathComponent(source.lastPathComponent)
        try Data(repeating: 2, count: 4096).write(to: existing)
        XCTAssertNotEqual(try FileCopier.checksum(of: source), try FileCopier.checksum(of: existing))
        var settings = ImportSettings()
        settings.destination = destination
        settings.organization = .flat
        let plan = ImportPlanner.plan(for: [MediaFile(url: source, fileSize: 4096)], settings: settings) {
            (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        }
        XCTAssertEqual(plan.count, 1, "Different photos must both be retained")
    }

    func testCopyMustPreserveDestinationCreatedAfterPlanning() throws {
        let source = dir.appendingPathComponent("source.jpg")
        let destination = dir.appendingPathComponent("dest.jpg")
        try Data("new photo".utf8).write(to: source)
        let previous = Data("existing photo".utf8)
        try previous.write(to: destination)
        _ = try? FileCopier.copy(from: source, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), previous)
    }

    private func foreignSidecar() throws -> URL {
        let source = dir.appendingPathComponent("DSC001.ARW")
        let xml = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"><rdf:Description xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" xmlns:xmp="http://ns.adobe.com/xap/1.0/" crs:Exposure2012="1.25" xmp:Rating="3"/></rdf:RDF></x:xmpmeta>
        """
        try Data(xml.utf8).write(to: XMPSidecar.url(for: source))
        return source
    }

    func testRatingUpdateMustPreserveForeignXMPProperties() throws {
        let source = try foreignSidecar()
        try XMPSidecar.write(FileMark(rating: .five), for: source)
        let xml = try String(contentsOf: XMPSidecar.url(for: source))
        XCTAssertTrue(xml.contains("crs:Exposure2012=\"1.25\""))
    }

    func testClearingRatingMustPreserveForeignSidecar() throws {
        let source = try foreignSidecar()
        try XMPSidecar.write(FileMark(), for: source)
        XCTAssertTrue(XMPSidecar.exists(for: source))
    }

    func testExportToSourceMustNotChangeOriginal() async throws {
        let source = dir.appendingPathComponent("original.jpg")
        let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
        try CIContext().writeJPEGRepresentation(of: image, to: source, colorSpace: CGColorSpaceCreateDeviceRGB())
        let before = try FileCopier.checksum(of: source)
        var adjustments = ImageAdjustments()
        adjustments.exposure = -70
        try? await ImageProcessor().export(url: source, adjustments: adjustments, settings: ExportSettings(), to: source)
        XCTAssertEqual(try FileCopier.checksum(of: source), before)
    }
}

private actor AuditBlockingThumbnailService: ThumbnailService {
    private var pending: [URL: CheckedContinuation<CGImage?, Never>] = [:]
    func thumbnail(for url: URL, size: CGSize) async -> CGImage? {
        await withCheckedContinuation { pending[url] = $0 }
    }
    func hasStarted(_ url: URL) -> Bool { pending[url] != nil }
    func release(_ url: URL) { pending.removeValue(forKey: url)?.resume(returning: nil) }
}

@MainActor
final class PreviewPriorityRegressionTests: XCTestCase {
    func testInteractiveRequestMustBypassQueuedPrefetch() async {
        let service = AuditBlockingThumbnailService()
        let provider = ThumbnailProvider(service: service)
        let a = URL(fileURLWithPath: "/tmp/siftly-audit-a.ARW")
        let b = URL(fileURLWithPath: "/tmp/siftly-audit-b.ARW")
        let size = CGSize(width: 1600, height: 1600)
        let first = Task { await provider.previewImage(for: a, pointSize: size, prefetch: true) }
        while !(await service.hasStarted(a)) { await Task.yield() }
        let queued = Task { await provider.previewImage(for: b, pointSize: size, prefetch: true) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let interactive = Task { await provider.previewImage(for: b, pointSize: size) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let startedBeforeRelease = await service.hasStarted(b)
        XCTAssertTrue(startedBeforeRelease, "Interactive preview is blocked by unrelated prefetch")
        await service.release(a)
        while !(await service.hasStarted(b)) { await Task.yield() }
        await service.release(b)
        _ = await first.value
        _ = await queued.value
        _ = await interactive.value
    }
}
