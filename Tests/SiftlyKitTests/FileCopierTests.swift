import XCTest
@testable import SiftlyKit

final class FileCopierTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("siftly-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    private func write(_ name: String, bytes: Int) throws -> URL {
        let url = dir.appendingPathComponent(name)
        var data = Data(count: bytes)
        for i in stride(from: 0, to: bytes, by: 997) { data[i] = UInt8(i % 251) }
        try data.write(to: url)
        return url
    }

    func testCopyReproducesContentExactly() throws {
        let source = try write("a.bin", bytes: 300_000)
        let destination = dir.appendingPathComponent("out/a.bin")

        let digest = try FileCopier.copy(from: source, to: destination)

        XCTAssertEqual(try Data(contentsOf: destination), try Data(contentsOf: source))
        XCTAssertEqual(digest, try FileCopier.checksum(of: source))
        XCTAssertEqual(digest, try FileCopier.checksum(of: destination))
    }

    /// Files bigger than one chunk exercise the streaming loop, which is where
    /// a truncation bug would actually show up.
    func testCopyHandlesFilesLargerThanOneChunk() throws {
        let size = FileCopier.chunkSize * 2 + 12_345
        let source = try write("big.bin", bytes: size)
        let destination = dir.appendingPathComponent("big-out.bin")

        try FileCopier.copy(from: source, to: destination)

        let copied = try FileHandle(forReadingFrom: destination).seekToEnd()
        XCTAssertEqual(Int(copied), size)
        XCTAssertEqual(
            try FileCopier.checksum(of: destination), try FileCopier.checksum(of: source)
        )
    }

    func testCopyCreatesMissingParentFolders() throws {
        let source = try write("b.bin", bytes: 1000)
        let destination = dir.appendingPathComponent("2026/2026-08/deep/b.bin")
        try FileCopier.copy(from: source, to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    /// A half-written file must never be left behind — the user would have no
    /// way to tell it apart from a finished import.
    func testAbortingRemovesThePartialFile() throws {
        let source = try write("c.bin", bytes: FileCopier.chunkSize * 3)
        let destination = dir.appendingPathComponent("partial.bin")

        var seen = 0
        XCTAssertThrowsError(
            try FileCopier.copy(from: source, to: destination) { _ in
                seen += 1
                return seen < 2      // abort part way through
            }
        ) { XCTAssertTrue($0 is CancellationError) }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.path),
            "a cancelled copy must not leave a partial file"
        )
    }

    /// Capture time has to survive the copy, or dated folders and sorting break
    /// on the imported set.
    func testModificationDateIsPreserved() throws {
        let source = try write("d.bin", bytes: 500)
        let when = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: source.path)

        let destination = dir.appendingPathComponent("d-out.bin")
        try FileCopier.copy(from: source, to: destination)

        let copied = try destination.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        XCTAssertEqual(copied?.timeIntervalSince1970 ?? 0, when.timeIntervalSince1970, accuracy: 1)
    }

    func testMissingSourceThrowsAReadableError() {
        let missing = dir.appendingPathComponent("nope.bin")
        XCTAssertThrowsError(
            try FileCopier.copy(from: missing, to: dir.appendingPathComponent("x.bin"))
        ) { error in
            XCTAssertEqual(error as? ImportError, .cannotReadSource("nope.bin"))
        }
    }

    /// Corruption in transit has to be detectable: a changed byte must change
    /// the digest, which is what the verify step compares.
    func testChecksumDetectsASingleChangedByte() throws {
        let source = try write("e.bin", bytes: 10_000)
        let original = try FileCopier.checksum(of: source)

        var data = try Data(contentsOf: source)
        data[5_000] = data[5_000] &+ 1
        try data.write(to: source)

        XCTAssertNotEqual(try FileCopier.checksum(of: source), original)
    }

    func testVerifiedCopyPublishesOnlyAfterCompletion() throws {
        let source = try write("verified.bin", bytes: FileCopier.chunkSize + 50)
        let destination = dir.appendingPathComponent("verified-out.bin")
        try FileCopier.copy(from: source, to: destination, verifies: true) { _ in
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            return true
        }
        XCTAssertEqual(try FileCopier.checksum(of: destination), try FileCopier.checksum(of: source))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix(".siftly-") })
    }

    func testDestinationCreatedDuringCopyIsNeverReplaced() throws {
        let source = try write("race.bin", bytes: 100)
        let destination = dir.appendingPathComponent("race-out.bin")
        let existing = Data("other application".utf8)
        XCTAssertThrowsError(try FileCopier.copy(from: source, to: destination, verifies: true) { _ in
            try! existing.write(to: destination)
            return true
        })
        XCTAssertEqual(try Data(contentsOf: destination), existing)
    }

    func testDanglingSymlinkDestinationIsPreserved() throws {
        let source = try write("link-source.bin", bytes: 100)
        let target = dir.appendingPathComponent("absent.bin")
        let destination = dir.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)
        XCTAssertThrowsError(try FileCopier.copy(from: source, to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), target.path)
    }

    func testChecksumOfEmptyFileIsTheKnownSHA256() throws {
        let empty = try write("empty.bin", bytes: 0)
        XCTAssertEqual(
            try FileCopier.checksum(of: empty),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }
}
