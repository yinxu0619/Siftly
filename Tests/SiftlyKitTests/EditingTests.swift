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

    func testGeometryFieldsAffectIdentityAndFlag() {
        var a = ImageAdjustments()
        XCTAssertFalse(a.hasGeometry)
        XCTAssertTrue(a.isIdentity)

        a.rotationQuarters = 1
        XCTAssertTrue(a.hasGeometry)
        XCTAssertFalse(a.isIdentity)

        var b = ImageAdjustments()
        b.straighten = 3.5
        XCTAssertTrue(b.hasGeometry)

        var c = ImageAdjustments()
        c.cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        XCTAssertTrue(c.hasGeometry)
        XCTAssertFalse(c.isIdentity)

        var d = ImageAdjustments()
        d.flipHorizontal = true
        XCTAssertTrue(d.hasGeometry)
    }

    func testAdjustmentsRoundTripEncodesGeometry() throws {
        var a = ImageAdjustments()
        a.rotationQuarters = 3
        a.straighten = -7.2
        a.flipHorizontal = true
        a.cropRect = CGRect(x: 0.05, y: 0.1, width: 0.6, height: 0.7)
        let data = try JSONEncoder().encode(a)
        let decoded = try JSONDecoder().decode(ImageAdjustments.self, from: data)
        XCTAssertEqual(decoded, a)
    }

    func testExportFormatQualitySupport() {
        XCTAssertTrue(ExportFormat.jpeg.supportsQuality)
        XCTAssertTrue(ExportFormat.heic.supportsQuality)
        XCTAssertFalse(ExportFormat.png.supportsQuality)
        XCTAssertFalse(ExportFormat.tiff.supportsQuality)
    }
}
