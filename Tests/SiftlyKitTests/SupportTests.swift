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

    /// The mount point must be stripped as a prefix only. Replacing every
    /// occurrence would mangle paths that repeat the volume name deeper down,
    /// producing keys that collide across unrelated files.
    func testLibraryKeyStripsMountPointOnlyAsPrefix() {
        let volumeURL = URL(fileURLWithPath: "/Volumes/NO NAME")
        let fileURL = URL(fileURLWithPath: "/Volumes/NO NAME/DCIM/NO NAME/DSC001.ARW")
        let key = LibraryStore.key(volumeID: "id", fileURL: fileURL, volumeURL: volumeURL)
        XCTAssertEqual(key, "id::/DCIM/NO NAME/DSC001.ARW")
    }

    func testLibraryKeyKeepsPathWhenOutsideVolume() {
        let volumeURL = URL(fileURLWithPath: "/Volumes/CARD")
        let fileURL = URL(fileURLWithPath: "/Users/me/DSC001.ARW")
        let key = LibraryStore.key(volumeID: "id", fileURL: fileURL, volumeURL: volumeURL)
        XCTAssertEqual(key, "id::/Users/me/DSC001.ARW")
    }

    /// The slider is continuous but decodes must not be: requests snap up to a
    /// fixed bucket so dragging it doesn't re-decode the whole visible grid.
    /// Buckets are in points — `ThumbnailService` applies the Retina scale, so
    /// pre-multiplying here would decode at 4x the pixels needed.
    func testThumbnailBucketsSnapUpAndClamp() {
        XCTAssertEqual(ThumbnailProvider.bucket(forPoints: 90), 128)
        XCTAssertEqual(ThumbnailProvider.bucket(forPoints: 128), 128)
        XCTAssertEqual(ThumbnailProvider.bucket(forPoints: 129), 192)
        XCTAssertEqual(ThumbnailProvider.bucket(forPoints: 260), 384)
        XCTAssertEqual(ThumbnailProvider.bucket(forPoints: 4000), 512)  // clamped
    }

    /// The whole point of the per-card namespace: two freshly formatted exFAT
    /// cards both mount as "NO NAME" with no volume UUID, and must not share
    /// one set of ratings. The name is excluded so renaming a card keeps them.
    func testVolumeIdentityPrefersUUID() {
        let id = MacVolumeService.identity(
            uuid: "E982C186-0000",
            volumeCreationDate: Date(timeIntervalSince1970: 1),
            mountPath: "/Volumes/NO NAME"
        )
        XCTAssertEqual(id, "E982C186-0000")
    }

    func testVolumeIdentityFallsBackToCreationDateNotMountPath() {
        let a = MacVolumeService.identity(
            uuid: nil,
            volumeCreationDate: Date(timeIntervalSince1970: 1_700_000_000),
            mountPath: "/Volumes/NO NAME"
        )
        let b = MacVolumeService.identity(
            uuid: nil,
            volumeCreationDate: Date(timeIntervalSince1970: 1_800_000_000),
            mountPath: "/Volumes/NO NAME"
        )
        XCTAssertEqual(a, "created-1700000000")
        XCTAssertNotEqual(a, b, "two cards sharing a mount path must not share an identity")
    }

    func testVolumeIdentityIsStableAcrossRename() {
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(
            MacVolumeService.identity(uuid: nil, volumeCreationDate: created, mountPath: "/Volumes/NO NAME"),
            MacVolumeService.identity(uuid: nil, volumeCreationDate: created, mountPath: "/Volumes/SHOOT-01")
        )
    }

    /// Last resort only. If this fires for a real card, the exFAT serial number
    /// is needed instead — the mount path collides across cards.
    func testVolumeIdentityFallsBackToMountPathWhenNothingElseIsAvailable() {
        XCTAssertEqual(
            MacVolumeService.identity(uuid: nil, volumeCreationDate: nil, mountPath: "/Volumes/NO NAME"),
            "/Volumes/NO NAME"
        )
        XCTAssertEqual(
            MacVolumeService.identity(uuid: "", volumeCreationDate: nil, mountPath: "/Volumes/X"),
            "/Volumes/X"
        )
    }

    func testFileMarkEmptiness() {
        XCTAssertTrue(FileMark().isEmpty)
        XCTAssertFalse(FileMark(rating: .three, label: .none).isEmpty)
        XCTAssertFalse(FileMark(rating: .none, label: .red).isEmpty)
    }
}
