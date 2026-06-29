import XCTest
import CoreGraphics
@testable import SiftlyKit

final class EditingTests: XCTestCase {
    func testIdentityAdjustmentsIsIdentity() {
        XCTAssertTrue(ImageAdjustments().isIdentity)
        var a = ImageAdjustments()
        a.exposure = 10
        XCTAssertFalse(a.isIdentity)
    }

    func testToneCurveIdentitySamplesLinearly() {
        let curve = ToneCurve.identity
        XCTAssertTrue(curve.isIdentity)
        XCTAssertEqual(curve.sample(0), 0, accuracy: 0.0001)
        XCTAssertEqual(curve.sample(0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(curve.sample(1), 1, accuracy: 0.0001)
    }

    func testToneCurveInterpolatesMidPoint() {
        // A point that lifts the midtones.
        let curve = ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.7), CGPoint(x: 1, y: 1)])
        XCTAssertFalse(curve.isIdentity)
        XCTAssertEqual(curve.sample(0.5), 0.7, accuracy: 0.0001)
        XCTAssertEqual(curve.sample(0.25), 0.35, accuracy: 0.0001) // halfway up first segment
    }

    func testToneCurveKeepsPointsSorted() {
        let curve = ToneCurve(points: [CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.4)])
        XCTAssertEqual(curve.points.map { $0.x }, [0, 0.5, 1])
    }

    func testCurvesDataHasExpectedByteCount() {
        let data = ToneCurve.identity.curvesData(count: 32)
        // 32 samples * 3 channels * 4 bytes (Float32).
        XCTAssertEqual(data.count, 32 * 3 * MemoryLayout<Float>.size)
    }

    func testExportFormatQualitySupport() {
        XCTAssertTrue(ExportFormat.jpeg.supportsQuality)
        XCTAssertTrue(ExportFormat.heic.supportsQuality)
        XCTAssertFalse(ExportFormat.png.supportsQuality)
        XCTAssertFalse(ExportFormat.tiff.supportsQuality)
    }
}
