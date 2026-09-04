import XCTest
import CoreImage
@testable import SiftlyKit

#if os(macOS)
final class ImageProcessorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("siftly-proc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Writes a real JPEG so the processor exercises its actual decode path.
    private func makeJPEG(width: Int, height: Int, name: String = "src.jpg") throws -> URL {
        let image = CIImage(color: .red).cropped(
            to: CGRect(x: 0, y: 0, width: width, height: height)
        )
        let url = dir.appendingPathComponent(name)
        try CIContext().writeJPEGRepresentation(
            of: image, to: url, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]
        )
        return url
    }

    func testReportsFullSourcePixelSize() async throws {
        let url = try makeJPEG(width: 1200, height: 800)
        let size = await ImageProcessor().sourcePixelSize(url)
        XCTAssertEqual(size?.width, 1200)
        XCTAssertEqual(size?.height, 800)
    }

    /// The preview is rendered downscaled; the cached preview must not leak into
    /// the export, which has to come back at full resolution.
    func testPreviewIsDownscaledButExportStaysFullResolution() async throws {
        let url = try makeJPEG(width: 1200, height: 800)
        let processor = ImageProcessor()
        var adjustments = ImageAdjustments()
        adjustments.exposure = 20
        adjustments.hdr = 40          // exercises the scale-dependent radii
        adjustments.sharpen = 50

        let preview = await processor.renderPreview(
            url: url, adjustments: adjustments, maxDimension: 300
        )
        XCTAssertEqual(preview?.size.width, 300, "preview should honour maxDimension")

        let out = dir.appendingPathComponent("out.jpg")
        try await processor.export(
            url: url, adjustments: adjustments, settings: ExportSettings(), to: out
        )
        let exported = CIImage(contentsOf: out)
        XCTAssertEqual(exported?.extent.width, 1200, "export must not inherit the preview scale")
    }

    /// Rendering the preview first must not poison the export cache, and vice
    /// versa — the two sources are cached independently.
    func testPreviewAndExportCachesAreIndependent() async throws {
        let url = try makeJPEG(width: 1000, height: 1000)
        let processor = ImageProcessor()

        _ = await processor.renderPreview(url: url, adjustments: .identity, maxDimension: 200)
        let out = dir.appendingPathComponent("a.jpg")
        try await processor.export(url: url, adjustments: .identity, settings: ExportSettings(), to: out)
        XCTAssertEqual(CIImage(contentsOf: out)?.extent.width, 1000)

        // Preview again after the export; still downscaled, still correct.
        let again = await processor.renderPreview(url: url, adjustments: .identity, maxDimension: 200)
        XCTAssertEqual(again?.size.width, 200)
        let size = await processor.sourcePixelSize(url)
        XCTAssertEqual(size?.width, 1000)
    }

    func testExportHonoursTheResizeSetting() async throws {
        let url = try makeJPEG(width: 1600, height: 1200)
        let out = dir.appendingPathComponent("small.jpg")
        try await ImageProcessor().export(
            url: url,
            adjustments: .identity,
            settings: ExportSettings(format: .jpeg, quality: 0.9, maxLongEdge: 800),
            to: out
        )
        XCTAssertEqual(CIImage(contentsOf: out)?.extent.width, 800)
    }

    /// Crop is stored normalized, so it must land in the same place regardless
    /// of the resolution it is applied at.
    func testCropIsResolutionIndependent() async throws {
        let url = try makeJPEG(width: 1000, height: 1000)
        var adjustments = ImageAdjustments()
        adjustments.cropRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)

        let out = dir.appendingPathComponent("cropped.jpg")
        try await ImageProcessor().export(
            url: url, adjustments: adjustments, settings: ExportSettings(), to: out
        )
        XCTAssertEqual(CIImage(contentsOf: out)?.extent.width, 500)
    }
}
#endif
