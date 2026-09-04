import XCTest
@testable import SiftlyKit

final class ImportPlannerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/Users/me/Pictures/Import")

    private func file(_ path: String, size: Int64 = 100, date: Date? = nil) -> MediaFile {
        var f = MediaFile(
            url: URL(fileURLWithPath: path),
            fileSize: size,
            modificationDate: date ?? Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12 UTC
        )
        f.volumeID = "card"
        return f
    }

    private func settings(
        _ organization: ImportOrganization = .flat
    ) -> ImportSettings {
        var s = ImportSettings()
        s.destination = root
        s.organization = organization
        return s
    }

    private func plan(
        _ files: [MediaFile],
        _ settings: ImportSettings,
        existing: [String: Int64] = [:]
    ) -> ImportPlan {
        ImportPlanner.plan(for: files, settings: settings) { existing[$0.path] }
    }

    // MARK: - Layout

    func testFlatLayoutPutsEverythingInTheRoot() {
        let result = plan([file("/card/DCIM/DSC001.ARW")], settings(.flat))
        XCTAssertEqual(result.items.first?.destination.path, "\(root.path)/DSC001.ARW")
    }

    func testDateLayoutUsesAStableFolderNameRegardlessOfLocale() {
        let day = Date(timeIntervalSince1970: 1_755_000_000)
        let result = plan([file("/card/DCIM/DSC001.ARW", date: day)], settings(.byDate))
        let folder = result.items.first!.destination.deletingLastPathComponent().lastPathComponent
        // yyyy-MM-dd, ASCII digits, whatever the user's locale is.
        XCTAssertEqual(folder.count, 10)
        XCTAssertEqual(folder.filter { $0 == "-" }.count, 2)
        XCTAssertTrue(folder.allSatisfy { $0.isNumber || $0 == "-" })
    }

    func testKindLayoutSeparatesRawJpegAndVideo() {
        let files = [
            file("/card/DSC001.ARW"), file("/card/DSC001.JPG"), file("/card/DJI_1.MP4")
        ]
        let result = plan(files, settings(.byDateAndKind))
        let kinds = result.items.map { $0.destination.deletingLastPathComponent().lastPathComponent }
        XCTAssertEqual(kinds, ["RAW", "JPEG", "Video"])
    }

    func testYearMonthLayoutNestsTwoLevels() {
        let result = plan([file("/card/DSC001.ARW")], settings(.byYearMonth))
        let path = result.items.first!.destination.deletingLastPathComponent()
        XCTAssertEqual(path.lastPathComponent.count, 7)                       // yyyy-MM
        XCTAssertEqual(path.deletingLastPathComponent().lastPathComponent.count, 4)  // yyyy
    }

    // MARK: - Collisions

    /// Re-importing the same card must be a no-op, not a pile of "-1" copies.
    func testIdenticalFileAtDestinationIsSkipped() {
        let f = file("/card/DSC001.ARW", size: 100)
        let result = plan([f], settings(.flat), existing: ["\(root.path)/DSC001.ARW": 100])
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.skipped.map(\.reason), [.alreadyImported])
    }

    /// Same name but a different file: must not overwrite.
    func testDifferentFileWithTheSameNameIsRenamed() {
        let f = file("/card/DSC001.ARW", size: 999)
        let result = plan([f], settings(.flat), existing: ["\(root.path)/DSC001.ARW": 100])
        XCTAssertEqual(result.items.first?.destination.path, "\(root.path)/DSC001-1.ARW")
        XCTAssertTrue(result.skipped.isEmpty)
    }

    /// Two cards routinely hold different photos under the same name; the
    /// filesystem probe can't catch that because neither is on disk yet.
    func testTwoSourcesMappingToOneDestinationAreBothKept() {
        let files = [
            file("/cardA/DCIM/DSC001.ARW", size: 111),
            file("/cardB/DCIM/DSC001.ARW", size: 222)
        ]
        let result = plan(files, settings(.flat))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(
            Set(result.items.map { $0.destination.lastPathComponent }),
            ["DSC001.ARW", "DSC001-1.ARW"]
        )
    }

    func testCollisionsKeepWalkingUntilAFreeName() {
        let f = file("/card/DSC001.ARW", size: 999)
        let existing: [String: Int64] = [
            "\(root.path)/DSC001.ARW": 100,
            "\(root.path)/DSC001-1.ARW": 100,
            "\(root.path)/DSC001-2.ARW": 100
        ]
        let result = plan([f], settings(.flat), existing: existing)
        XCTAssertEqual(result.items.first?.destination.lastPathComponent, "DSC001-3.ARW")
    }

    /// A rename should still be able to land on an identical earlier copy and
    /// be recognised as already imported.
    func testRenameWalkStopsOnAMatchingCopy() {
        let f = file("/card/DSC001.ARW", size: 555)
        let existing: [String: Int64] = [
            "\(root.path)/DSC001.ARW": 100,     // different file
            "\(root.path)/DSC001-1.ARW": 555    // this is our file, already here
        ]
        let result = plan([f], settings(.flat), existing: existing)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.skipped.first?.reason, .alreadyImported)
    }

    // MARK: - Misc

    func testNoDestinationYieldsAnEmptyPlan() {
        var s = ImportSettings()
        s.destination = nil
        XCTAssertTrue(plan([file("/card/DSC001.ARW")], s).isEmpty)
    }

    func testTotalBytesSumsTheSources() {
        let files = [file("/card/A.ARW", size: 300), file("/card/B.ARW", size: 700)]
        XCTAssertEqual(plan(files, settings()).totalBytes, 1000)
    }

    func testExtensionlessFilesAreHandled() {
        let result = plan([file("/card/NOEXT")], settings(.flat))
        XCTAssertEqual(result.items.first?.destination.lastPathComponent, "NOEXT")
    }
}
