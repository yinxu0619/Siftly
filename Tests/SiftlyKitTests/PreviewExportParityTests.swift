import XCTest
import CoreImage
@testable import SiftlyKit

#if os(macOS)
/// Guards the editor's WYSIWYG promise.
///
/// Several Core Image parameters in the pipeline are absolute pixel radii, so a
/// radius tuned for a 45MP export covers a far larger share of the ~1800px live
/// preview. Before `renderScale` existed, HDR / shadows / sharpening looked
/// materially different in the preview than in the exported file.
///
/// This renders both paths from one source and compares them at a common size.
/// The threshold is deliberately loose — resampling and JPEG differences mean
/// the two can never be identical — but it sits far below the drift the
/// unscaled pipeline produced (measured: ~120/255 unscaled vs ~37/255 scaled).
final class PreviewExportParityTests: XCTestCase {
    private let commonSize: CGFloat = 400

    func testPreviewMatchesExportForScaleDependentFilters() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("siftly-parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = try makeStructuredImage(in: dir, size: 2000)

        // Every adjustment here depends on a pixel radius.
        var adjustments = ImageAdjustments()
        adjustments.hdr = 80
        adjustments.sharpen = 80
        adjustments.shadows = 60

        let processor = ImageProcessor()
        guard let preview = await processor.renderPreview(
            url: source, adjustments: adjustments, maxDimension: commonSize
        ) else {
            return XCTFail("preview render failed")
        }
        let exported = dir.appendingPathComponent("export.jpg")
        try await processor.export(
            url: source, adjustments: adjustments, settings: ExportSettings(), to: exported
        )

        let drift = try meanAbsoluteDifference(
            between: try XCTUnwrap(CIImage(contentsOf: exported)),
            and: try XCTUnwrap(cgImage(of: preview))
        )
        XCTAssertLessThan(
            drift, 70,
            "preview drifted \(drift)/255 from the export; pixel-radius filters are probably not being scaled"
        )
    }

    // MARK: - Helpers

    /// Low-frequency structure: it survives downscaling (noise would decorrelate
    /// and swamp the measurement) while still giving the local-contrast filters
    /// edges to work on.
    private func makeStructuredImage(in dir: URL, size: CGFloat) throws -> URL {
        let checker = CIFilter(name: "CICheckerboardGenerator")!
        checker.setValue(CIVector(x: 0, y: 0), forKey: "inputCenter")
        checker.setValue(80.0, forKey: "inputWidth")
        checker.setValue(CIColor(red: 0.2, green: 0.3, blue: 0.5), forKey: "inputColor0")
        checker.setValue(CIColor(red: 0.85, green: 0.8, blue: 0.7), forKey: "inputColor1")
        let image = checker.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let url = dir.appendingPathComponent("source.jpg")
        try CIContext().writeJPEGRepresentation(
            of: image, to: url, colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]
        )
        return url
    }

    private func cgImage(of image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Mean absolute per-channel difference (0...255) after bringing both images
    /// to `commonSize`.
    private func meanAbsoluteDifference(between full: CIImage, and preview: CGImage) throws -> Double {
        let rect = CGRect(x: 0, y: 0, width: commonSize, height: commonSize)

        let scaler = CIFilter(name: "CILanczosScaleTransform")!
        scaler.setValue(full, forKey: kCIInputImageKey)
        scaler.setValue(commonSize / full.extent.width, forKey: kCIInputScaleKey)
        let shrunk = try XCTUnwrap(scaler.outputImage).cropped(to: rect)

        let difference = CIFilter(name: "CIDifferenceBlendMode")!
        difference.setValue(shrunk, forKey: kCIInputImageKey)
        difference.setValue(CIImage(cgImage: preview).cropped(to: rect), forKey: kCIInputBackgroundImageKey)

        let average = CIFilter(name: "CIAreaAverage")!
        average.setValue(try XCTUnwrap(difference.outputImage), forKey: kCIInputImageKey)
        average.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            try XCTUnwrap(average.outputImage),
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / 3.0
    }
}
#endif
