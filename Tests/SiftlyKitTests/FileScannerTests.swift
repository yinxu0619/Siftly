import XCTest
@testable import SiftlyKit

#if os(macOS)
final class FileScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiftlyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func touch(_ name: String) throws {
        let url = tempDir.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
    }

    func testFiltersByExtensionAndBatches() throws {
        for i in 0..<10 {
            try touch(String(format: "DSC%03d.ARW", i))
            try touch(String(format: "DSC%03d.JPG", i))
        }
        try touch("notes.txt") // should be filtered out

        let service = MacFileSystemService()
        var batches: [[MediaFile]] = []
        try service.scanMediaFiles(
            in: tempDir,
            extensions: ["arw", "jpg"],
            batchSize: 4
        ) { batches.append($0) }

        let all = batches.flatMap { $0 }
        XCTAssertEqual(all.count, 20)
        XCTAssertFalse(all.contains { $0.ext == "txt" })
        XCTAssertGreaterThan(batches.count, 1, "expected multiple batches")
        XCTAssertTrue(batches.dropLast().allSatisfy { $0.count == 4 })
    }

    func testConvenienceEnumerateReturnsAll() throws {
        try touch("A.JPG")
        try touch("B.JPG")
        let service = MacFileSystemService()
        let files = try service.enumerateMediaFiles(in: tempDir, extensions: ["jpg"])
        XCTAssertEqual(files.count, 2)
        XCTAssertNotNil(files.first?.fileSize)
    }
}
#endif
