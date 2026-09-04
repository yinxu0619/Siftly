import XCTest
@testable import SiftlyKit

/// Drives a fake card end to end: plan -> copy -> verify, the way an import run
/// does. The unit tests cover the pieces; this covers them working together.
final class ImportIntegrationTests: XCTestCase {
    private var card: URL!
    private var destination: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("siftly-e2e-\(UUID().uuidString)", isDirectory: true)
        card = base.appendingPathComponent("CARD/DCIM", isDirectory: true)
        destination = base.appendingPathComponent("Pictures", isDirectory: true)
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: card.deletingLastPathComponent().deletingLastPathComponent())
    }

    @discardableResult
    private func shoot(_ name: String, bytes: Int, on day: String) throws -> MediaFile {
        let url = card.appendingPathComponent(name)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 101) { data[i] = UInt8((i &+ name.count) % 251) }
        try data.write(to: url)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: day)!
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return MediaFile(
            url: url,
            fileSize: values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate
        )
    }

    /// Runs the copy loop the way `AppState` does, returning what landed.
    private func run(_ plan: ImportPlan) throws -> [URL] {
        var copied: [URL] = []
        for item in plan.items {
            let written = try FileCopier.copy(from: item.source.url, to: item.destination)
            let onDisk = try FileCopier.checksum(of: item.destination)
            XCTAssertEqual(written, onDisk, "\(item.source.name) failed verification")
            copied.append(item.destination)
        }
        return copied
    }

    private func settings(_ organization: ImportOrganization) -> ImportSettings {
        var s = ImportSettings()
        s.destination = destination
        s.organization = organization
        return s
    }

    private func plan(_ files: [MediaFile], _ settings: ImportSettings) -> ImportPlan {
        ImportPlanner.plan(for: files, settings: settings) { url in
            (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
        }
    }

    private func relativePaths() throws -> Set<String> {
        // Resolve both sides: the temp directory is reached through the
        // /var -> /private/var symlink, so the raw prefixes differ in length.
        let root = destination.resolvingSymlinksInPath().path
        var found: Set<String> = []
        let enumerator = FileManager.default.enumerator(
            at: destination, includingPropertiesForKeys: [.isRegularFileKey]
        )!
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            let path = url.resolvingSymlinksInPath().path
            found.insert(path.hasPrefix(root) ? String(path.dropFirst(root.count + 1)) : path)
        }
        return found
    }

    func testFullImportLandsInTheExpectedTree() throws {
        let files = [
            try shoot("DSC001.ARW", bytes: 5_000, on: "2026-08-17"),
            try shoot("DSC001.JPG", bytes: 2_000, on: "2026-08-17"),
            try shoot("DJI_0001.MP4", bytes: 9_000, on: "2026-08-18")
        ]

        let result = plan(files, settings(.byDateAndKind))
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.totalBytes, 16_000)

        try run(result)

        XCTAssertEqual(try relativePaths(), [
            "2026-08-17/RAW/DSC001.ARW",
            "2026-08-17/JPEG/DSC001.JPG",
            "2026-08-18/Video/DJI_0001.MP4"
        ])
    }

    /// Importing the same card twice must copy nothing the second time — the
    /// single most likely thing a user does by accident.
    func testSecondImportOfTheSameCardCopiesNothing() throws {
        let files = [
            try shoot("DSC001.ARW", bytes: 5_000, on: "2026-08-17"),
            try shoot("DSC002.ARW", bytes: 6_000, on: "2026-08-17")
        ]

        try run(plan(files, settings(.byDate)))
        let before = try relativePaths()

        let second = plan(files, settings(.byDate))
        XCTAssertTrue(second.isEmpty, "re-import should have nothing to do")
        XCTAssertEqual(second.skipped.count, 2)

        try run(second)
        XCTAssertEqual(try relativePaths(), before, "re-import must not add duplicates")
    }

    /// A different photo that happens to share a name must be kept, not
    /// silently overwritten.
    func testSameNameDifferentPhotoIsKeptAlongside() throws {
        let first = try shoot("DSC001.ARW", bytes: 5_000, on: "2026-08-17")
        try run(plan([first], settings(.flat)))

        // Reshoot: same name, different content and size.
        let second = try shoot("DSC001.ARW", bytes: 7_500, on: "2026-08-17")
        try run(plan([second], settings(.flat)))

        XCTAssertEqual(try relativePaths(), ["DSC001.ARW", "DSC001-1.ARW"])
        XCTAssertEqual(
            try FileCopier.checksum(of: destination.appendingPathComponent("DSC001-1.ARW")),
            try FileCopier.checksum(of: second.url)
        )
    }

    /// Two cards, same filenames, different photos — cross-card mode's normal
    /// case. Both must survive one run.
    func testTwoCardsWithClashingNamesBothImport() throws {
        let a = try shoot("DSC001.ARW", bytes: 4_000, on: "2026-08-17")
        let otherCard = card.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CARD2/DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: otherCard, withIntermediateDirectories: true)
        let bURL = otherCard.appendingPathComponent("DSC001.ARW")
        try Data(repeating: 7, count: 8_000).write(to: bURL)
        let b = MediaFile(url: bURL, fileSize: 8_000, modificationDate: a.modificationDate)

        let result = plan([a, b], settings(.flat))
        XCTAssertEqual(result.count, 2)
        try run(result)

        XCTAssertEqual(try relativePaths(), ["DSC001.ARW", "DSC001-1.ARW"])
    }
}
