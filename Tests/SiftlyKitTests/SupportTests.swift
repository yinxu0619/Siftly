import XCTest
@testable import SiftlyKit

final class SupportTests: XCTestCase {
    func testChunkedSplitsEvenly() {
        let chunks = Array(1...10).chunked(into: 4)
        XCTAssertEqual(chunks, [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10]])
    }

    func testChunkedHandlesEmpty() {
        XCTAssertEqual([Int]().chunked(into: 4), [])
    }

    func testLibraryKeyIsVolumeRelative() {
        let volumeURL = URL(fileURLWithPath: "/Volumes/CARD")
        let fileURL = URL(fileURLWithPath: "/Volumes/CARD/DCIM/DSC001.ARW")
        let key = LibraryStore.key(volumeID: "UUID-1", fileURL: fileURL, volumeURL: volumeURL)
        XCTAssertEqual(key, "UUID-1::/DCIM/DSC001.ARW")
    }

    func testFileMarkEmptiness() {
        XCTAssertTrue(FileMark().isEmpty)
        XCTAssertFalse(FileMark(rating: .three, label: .none).isEmpty)
        XCTAssertFalse(FileMark(rating: .none, label: .red).isEmpty)
    }
}
