import XCTest
@testable import SiftlyKit

final class LibraryStoreTests: XCTestCase {
    func testFlushPersistsLatestSnapshotAndDeletionAcrossReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("siftly-library-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("marks.json")
        let library = LibraryStore(fileURL: url)
        for rating in [Rating.one, .three, .five] { library.setMark(FileMark(rating: rating), forKey: "a") }
        library.setMark(FileMark(label: .red), forKey: "b")
        library.removeMarks(forKeys: ["b"])
        try library.flush()
        let reloaded = LibraryStore(fileURL: url)
        XCTAssertEqual(reloaded.mark(forKey: "a").rating, .five)
        XCTAssertTrue(reloaded.mark(forKey: "b").isEmpty)
    }

    func testSaveFailureIsReportedByFlushAndCallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("siftly-library-\(UUID())")
        try Data().write(to: root) // a file, so it cannot be the parent directory
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore(fileURL: root.appendingPathComponent("marks.json"))
        let reported = expectation(description: "Save error surfaced")
        library.onSaveError = { _ in reported.fulfill() }
        library.setMark(FileMark(rating: .five), forKey: "a")
        XCTAssertThrowsError(try library.flush())
        wait(for: [reported], timeout: 1)
    }
}
