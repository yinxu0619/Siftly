import XCTest
@testable import SiftlyKit

final class DeletionPlannerTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/Volumes/CARD/DCIM")

    private func file(_ name: String, size: Int64 = 1000) -> MediaFile {
        MediaFile(url: dir.appendingPathComponent(name), fileSize: size)
    }

    func testSelectingRAWIncludesPairedJPG() {
        let arw = file("DSC001.ARW")
        let jpg = file("DSC001.JPG")
        let files = [arw, jpg]
        let pairing = PairingEngine().computePairs(files, rule: .default)

        let plan = DeletionPlanner.plan(for: [arw.url], pairing: pairing, allFiles: files)
        XCTAssertEqual(plan.directlySelected.map { $0.url }, [arw.url])
        XCTAssertEqual(plan.pairedAdditions.map { $0.url }, [jpg.url])
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.totalSize, 2000)
    }

    func testNoDoubleCountWhenBothSelected() {
        let arw = file("DSC001.ARW")
        let jpg = file("DSC001.JPG")
        let files = [arw, jpg]
        let pairing = PairingEngine().computePairs(files, rule: .default)

        let plan = DeletionPlanner.plan(for: [arw.url, jpg.url], pairing: pairing, allFiles: files)
        XCTAssertEqual(plan.count, 2)
        XCTAssertTrue(plan.pairedAdditions.isEmpty)
    }

    func testUnpairedFileOnlyDeletesItself() {
        let png = file("LONE.PNG")
        let files = [png]
        let pairing = PairingEngine().computePairs(files, rule: .default)

        let plan = DeletionPlanner.plan(for: [png.url], pairing: pairing, allFiles: files)
        XCTAssertEqual(plan.count, 1)
        XCTAssertTrue(plan.pairedAdditions.isEmpty)
    }
}
