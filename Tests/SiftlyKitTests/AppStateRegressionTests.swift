import XCTest
import CoreGraphics
@testable import SiftlyKit

private final class TestVolumes: VolumeService {
    let volume: Volume
    init(_ root: URL) { volume = Volume(id: "test-card", name: "Test Card", url: root, isRemovable: true) }
    func currentRemovableVolumes() -> [Volume] { [volume] }
    func startObserving(onChange: @escaping () -> Void) {}
    func stopObserving() {}
}

private final class TestTrash: TrashService {
    let root: URL
    init(_ root: URL) { self.root = root }
    func moveToTrash(_ url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }
    func restoreItem(at trashURL: URL, to originalURL: URL) throws {
        try FileManager.default.moveItem(at: trashURL, to: originalURL)
    }
}

private final class NoThumbnails: ThumbnailService {
    func thumbnail(for url: URL, size: CGSize) async -> CGImage? { nil }
}

private final class LargeCardScanner: FileSystemService {
    let count: Int
    init(count: Int) { self.count = count }
    func scanMediaFiles(in directory: URL, extensions: Set<String>, batchSize: Int, onBatch: ([MediaFile]) -> Bool) throws {
        for start in stride(from: 0, to: count, by: batchSize) {
            let batch = (start..<min(start + batchSize, count)).map {
                MediaFile(url: directory.appendingPathComponent(String(format: "DSC%05d.JPG", $0)), fileSize: 100)
            }
            if !onBatch(batch) { return }
        }
    }
}

@MainActor
final class AppStateRegressionTests: XCTestCase {
    private func withApp(scanner: FileSystemService = MacFileSystemService(), expectedCount: Int = 2, _ body: (AppState, URL, LibraryStore) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: "/private/tmp/siftly-state-\(UUID())", isDirectory: true)
        let card = root.appendingPathComponent("card")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "siftly.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = card.appendingPathComponent("DSC001.JPG")
        try Data("photo".utf8).write(to: source)
        try Data("other".utf8).write(to: card.appendingPathComponent("DSC002.JPG"))
        let index = root.appendingPathComponent("marks.json")
        let key = LibraryStore.key(volumeID: "test-card", fileURL: source, volumeURL: card)
        let seeded = LibraryStore(fileURL: index)
        seeded.setMark(FileMark(rating: .four), forKey: key)
        try seeded.flush()
        let library = LibraryStore(fileURL: index)
        let app = AppState(volumeService: TestVolumes(card), fileSystem: scanner,
                           trash: TestTrash(root.appendingPathComponent("trash")),
                           thumbnails: ThumbnailProvider(service: NoThumbnails()), library: library, defaults: defaults)
        try await waitUntil { !app.isScanning && app.displayedFiles.count == expectedCount }
        try await body(app, card, library)
        app.flushPersistence()
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(predicate(), "State update timed out")
    }

    func testDeletionRemovesMarksLoadedInEarlierSessionAndUndoRestoresThem() async throws {
        try await withApp { app, card, library in
            let source = card.appendingPathComponent("DSC001.JPG")
            let file = try XCTUnwrap(app.file(for: source), "source=\(source.absoluteString), scanned=\(app.files.map { $0.url.absoluteString }), card=\(card.path)")
            XCTAssertEqual(app.mark(for: file).rating, .four)
            XCTAssertTrue(app.marks.isEmpty, "Exercise the lazy persisted-mark lookup")
            await app.performDeletion(app.planDeletion(for: [source]))
            let key = LibraryStore.key(volumeID: "test-card", fileURL: source, volumeURL: card)
            XCTAssertTrue(library.mark(forKey: key).isEmpty)
            app.undoLastDeletion()
            XCTAssertEqual(library.mark(forKey: key).rating, .four)
            try await self.waitUntil { !app.isScanning }
        }
    }

    func testBatchMarksWriteSidecarsAndRapidChangesKeepLatestValue() async throws {
        try await withApp { app, _, _ in
            app.writesXMPSidecars = true
            app.selectAll()
            app.setRatingForSelection(.two)
            app.setRatingForSelection(.five)
            app.setLabelForSelection(.red)
            app.flushPersistence()
            for file in app.files {
                let sidecar = try XCTUnwrap(XMPSidecar.read(for: file.url), "\((try? String(contentsOf: XMPSidecar.url(for: file.url))) ?? app.errorMessage ?? "missing sidecar")")
                XCTAssertEqual(sidecar.rating, .five)
                XCTAssertEqual(sidecar.label, .red)
            }
        }
    }

    func testChangedDestinationRejectsAnOldImportPlan() async throws {
        try await withApp { app, card, _ in
            let root = card.deletingLastPathComponent()
            let oldDestination = root.appendingPathComponent("old")
            app.importSettings.destination = oldDestination
            app.importSettings.organization = .flat
            let plan = await app.planImport(selectionOnly: false)
            XCTAssertEqual(plan.count, 2)
            app.importSettings.destination = root.appendingPathComponent("new")
            await app.performImport(plan)
            XCTAssertFalse(FileManager.default.fileExists(atPath: oldDestination.path))
            XCTAssertFalse(app.isImporting)
        }
    }

    func testLatestFilterAndPersistedRatingsDriveBackgroundDisplay() async throws {
        try await withApp { app, _, _ in
            app.searchText = "001"
            app.searchText = "002"
            try await self.waitUntil { app.displayedFiles.map(\.name) == ["DSC002.JPG"] }
            app.searchText = ""
            app.minRating = 4
            try await self.waitUntil { app.displayedFiles.map(\.name) == ["DSC001.JPG"] }
            let shown = try XCTUnwrap(app.displayedFiles.first)
            XCTAssertEqual(app.displayedPosition(of: shown.url), 0)
        }
    }

    func testLargeScanRetainsEveryBatchAndBuildsConsistentIndexes() async throws {
        try await withApp(scanner: LargeCardScanner(count: 10_007), expectedCount: 10_007) { app, _, _ in
            XCTAssertEqual(app.files.count, 10_007)
            for file in app.files { XCTAssertEqual(app.file(for: file.url), file) }
            app.sortKey = .name
            app.sortAscending = true
            try await self.waitUntil { app.displayedFiles.first?.name == "DSC00000.JPG" && app.displayedFiles.last?.name == "DSC10006.JPG" }
            for (index, file) in app.displayedFiles.enumerated() {
                XCTAssertEqual(app.displayedPosition(of: file.url), index)
            }
        }
    }

    func testCleanupRequiresVerificationEvenWhenPreferenceIsOff() {
        var settings = ImportSettings()
        settings.verifies = false
        XCTAssertFalse(settings.requiresVerification)
        settings.deletesAfterImport = true
        XCTAssertTrue(settings.requiresVerification)
    }
}
