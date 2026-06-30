import Foundation
import Combine
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Central observable application state. Wires together the platform services,
/// disk scanning, pairing, and user marks. UI observes this object.
/// Filter for the grid by file kind / pairing state.
public enum FormatFilter: String, CaseIterable, Identifiable {
    case all, raw, jpg, paired, unpaired
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return L10n.formatAll
        case .raw: return L10n.formatRAW
        case .jpg: return L10n.formatJPG
        case .paired: return L10n.formatPaired
        case .unpaired: return L10n.formatUnpaired
        }
    }
}

/// Sort key for the grid.
public enum SortKey: String, CaseIterable, Identifiable {
    case date, name, size
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .date: return L10n.sortDate
        case .name: return L10n.sortName
        case .size: return L10n.sortSize
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    /// Sentinel browse selection meaning "all mounted cards" (cross-card mode).
    public static let allCardsTag = "__ALL_CARDS__"

    // Services (platform abstraction layer)
    private let volumeService: VolumeService
    private let fileSystem: FileSystemService
    private let trash: TrashService
    public let thumbnails: ThumbnailProvider

    private let pairingEngine = PairingEngine()
    private let library = LibraryStore()
    /// Non-destructive image editor backend (Core Image).
    public let processor = ImageProcessor()

    // Published state
    @Published public private(set) var volumes: [Volume] = []
    /// Either a volume id, `allCardsTag`, or nil.
    @Published public var browseSelection: String?
    @Published public private(set) var files: [MediaFile] = []
    @Published public var selection: Set<URL> = []
    @Published public var currentFileURL: URL?
    /// File currently shown in the full-size preview viewer (nil = closed).
    @Published public var previewURL: URL?
    /// File currently open in the non-destructive editor (nil = closed).
    @Published public var editorURL: URL?
    /// True while an edited image is being rendered & written to disk.
    @Published public private(set) var isExporting = false
    /// Drives the delete confirmation sheet (toolbar / context menu / preview).
    @Published public var isShowingDeleteSheet = false
    /// Drives the "关于 / 赞助" sheet.
    @Published public var isShowingAbout = false
    @Published public var pairingRule: PairingRule = .default
    @Published public private(set) var pairing: PairingResult = .empty

    // Filter / sort / search state for the grid.
    @Published public var searchText: String = ""
    @Published public var formatFilter: FormatFilter = .all
    @Published public var minRating: Int = 0
    @Published public var labelFilter: ColorLabel?
    @Published public var sortKey: SortKey = .date
    @Published public var sortAscending: Bool = false
    @Published public private(set) var isScanning = false
    @Published public var statusMessage: String = L10n.Status.noCards
    /// User-facing error, surfaced as an alert. Cleared when dismissed.
    @Published public var errorMessage: String?
    /// Marks keyed by `volumeID::relativePath`, mirrored for SwiftUI updates.
    @Published public private(set) var marks: [String: FileMark] = [:]

    /// In-flight scan, validated by a token so stale results never repopulate.
    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()

    // Deletion progress (batched, non-blocking).
    @Published public private(set) var isDeleting = false
    @Published public private(set) var deletionDone = 0
    @Published public private(set) var deletionTotal = 0
    public var deletionProgress: Double {
        deletionTotal == 0 ? 0 : Double(deletionDone) / Double(deletionTotal)
    }

    // Undo support for the most recent deletion.
    private struct DeletedItem { let original: URL; let trashed: URL? }
    private var lastDeletedItems: [DeletedItem] = []
    @Published public private(set) var canUndo = false

    // User preferences (persisted in UserDefaults).
    private static let prefetchKey = "siftly.preview.prefetchCount"
    /// How many neighbors (per side) to preload around the viewed photo. 0 = off.
    @Published public var previewPrefetchCount: Int {
        didSet {
            let clamped = max(0, min(previewPrefetchCount, 20))
            if clamped != previewPrefetchCount { previewPrefetchCount = clamped; return }
            UserDefaults.standard.set(previewPrefetchCount, forKey: Self.prefetchKey)
            thumbnails.configurePreviewCache(count: previewPrefetchCount)
        }
    }

    private static let languageKey = "siftly.languageOverride"
    /// Selected interface language: `nil` (or "system") follows the OS; otherwise
    /// a locale identifier like "en" or "zh-Hans".
    @Published public var languageOverride: String? {
        didSet {
            UserDefaults.standard.set(languageOverride, forKey: Self.languageKey)
            L10n.overrideLocaleIdentifier = languageOverride
        }
    }

    /// Locales the UI offers an explicit choice for (besides "follow system").
    public static let supportedLanguages: [String] = ["en", "zh-Hans"]

    /// Pixel size used for the full-size preview (and its prefetch cache).
    public static let previewPixelSize = CGSize(width: 2600, height: 2600)

    public init() {
        let storedPrefetch = UserDefaults.standard.object(forKey: Self.prefetchKey) as? Int
        self.previewPrefetchCount = storedPrefetch ?? 3
        let storedLanguage = UserDefaults.standard.string(forKey: Self.languageKey)
        self.languageOverride = storedLanguage
        L10n.overrideLocaleIdentifier = storedLanguage

        #if os(macOS)
        self.volumeService = MacVolumeService()
        self.fileSystem = MacFileSystemService()
        self.trash = MacTrashService()
        self.thumbnails = ThumbnailProvider(service: MacThumbnailService())
        #elseif os(Windows)
        self.volumeService = WindowsVolumeService()
        self.fileSystem = WindowsFileSystemService()
        self.trash = WindowsTrashService()
        self.thumbnails = ThumbnailProvider(service: WindowsThumbnailService())
        #endif

        thumbnails.configurePreviewCache(count: previewPrefetchCount)

        volumeService.startObserving { [weak self] in
            self?.refreshVolumes()
        }
        refreshVolumes()
    }

    /// Preloads the photos adjacent to `url` (per the user's prefetch setting) so
    /// flipping to the next/previous photo in the viewer is instant.
    public func prefetchAdjacentPreviews(around url: URL) {
        let n = previewPrefetchCount
        guard n > 0 else { return }
        let list = displayedFiles
        guard let idx = list.firstIndex(where: { $0.url == url }) else { return }
        var urls: [URL] = []
        for step in 1...n {
            if idx + step < list.count { urls.append(list[idx + step].url) }
            if idx - step >= 0 { urls.append(list[idx - step].url) }
        }
        thumbnails.prefetchPreviews(urls, pixelSize: Self.previewPixelSize)
    }

    /// True when browsing/merging all cards (enables cross-card pairing).
    public var crossCardMode: Bool { browseSelection == Self.allCardsTag }

    public var selectedVolume: Volume? {
        guard let id = browseSelection, id != Self.allCardsTag else { return nil }
        return volumes.first { $0.id == id }
    }

    /// Volumes that the current browse scope targets.
    private var targetVolumes: [Volume] {
        if crossCardMode { return volumes }
        if let v = selectedVolume { return [v] }
        return []
    }

    // MARK: - Volumes

    public func refreshVolumes() {
        let current = volumeService.currentRemovableVolumes()
        volumes = current

        if crossCardMode {
            if current.isEmpty {
                scanTask?.cancel()
                resetBrowseState(message: L10n.Status.noCards)
                browseSelection = nil
            } else {
                // Re-merge across the (possibly changed) set of cards.
                rescanCurrentScope()
            }
            return
        }

        if let id = browseSelection, !current.contains(where: { $0.id == id }) {
            // Previously selected card was removed mid-session.
            scanTask?.cancel()
            resetBrowseState(message: L10n.Status.cardRemoved)
            browseSelection = nil
        }

        if browseSelection == nil, let first = current.first {
            selectVolume(first)
        } else if current.isEmpty {
            statusMessage = L10n.Status.noCards
        }
    }

    private func resetBrowseState(message: String) {
        files = []
        selection = []
        currentFileURL = nil
        pairing = .empty
        isScanning = false
        statusMessage = message
    }

    /// Manual refresh from the toolbar: re-detect volumes and rescan the scope.
    public func manualRefresh() {
        refreshVolumes()
        rescanCurrentScope()
    }

    public func selectVolume(_ volume: Volume) {
        if browseSelection == volume.id && !files.isEmpty { return }
        browseSelection = volume.id
        beginScan()
    }

    /// Switches to cross-card mode: merge and browse all mounted cards.
    public func selectAllCards() {
        browseSelection = Self.allCardsTag
        beginScan()
    }

    private func rescanCurrentScope() {
        guard !targetVolumes.isEmpty else { return }
        beginScan()
    }

    // MARK: - Scanning

    private func beginScan() {
        let vols = targetVolumes
        guard !vols.isEmpty else { return }

        scanTask?.cancel()
        let token = UUID()
        scanID = token

        isScanning = true
        files = []
        pairing = .empty
        selection = []
        currentFileURL = nil

        var rule = pairingRule
        rule.crossLocation = crossCardMode
        let extensions = rule.allExtensions.union(MediaCatalog.imageExtensions)
        let fs = fileSystem
        let scopeName = crossCardMode ? L10n.allStorageCards : (vols.first?.name ?? "")
        statusMessage = L10n.Status.scanning(scopeName)

        scanTask = Task { [weak self] in
            // Stream batches (off-main) from each target volume, stamping the
            // owning volume so cross-card pairing and mark keys work.
            let stream = AsyncThrowingStream<[MediaFile], Error> { continuation in
                Task.detached(priority: .userInitiated) {
                    do {
                        for vol in vols {
                            try fs.scanMediaFiles(in: vol.url, extensions: extensions, batchSize: 256) { batch in
                                let stamped = batch.map { file -> MediaFile in
                                    var m = file
                                    m.volumeID = vol.id
                                    m.volumeName = vol.name
                                    m.volumeURL = vol.url
                                    return m
                                }
                                continuation.yield(stamped)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            do {
                var collected: [MediaFile] = []
                for try await batch in stream {
                    if Task.isCancelled { return }
                    guard let self, self.scanID == token else { return }
                    collected.append(contentsOf: batch)
                    self.files.append(contentsOf: batch)
                    self.statusMessage = L10n.Status.scanningFound(collected.count)
                }

                if Task.isCancelled { return }
                guard let self, self.scanID == token else { return }
                let sorted = collected.sorted { lhs, rhs in
                    (lhs.modificationDate ?? .distantPast) > (rhs.modificationDate ?? .distantPast)
                }
                self.files = sorted
                self.pairing = self.pairingEngine.computePairs(sorted, rule: rule)
                self.isScanning = false
                let pairedCount = sorted.filter { self.pairing.isPaired($0.url) }.count
                if self.crossCardMode {
                    self.statusMessage = L10n.Status.multiCardSummary(vols.count, sorted.count, pairedCount)
                } else {
                    self.statusMessage = L10n.Status.fileCount(sorted.count)
                }
            } catch {
                if Task.isCancelled { return }
                guard let self, self.scanID == token else { return }
                self.isScanning = false
                self.files = []
                self.statusMessage = L10n.Status.scanFailed
                self.errorMessage = Self.friendlyMessage(for: error, context: L10n.Error.scanContext)
            }
        }
    }

    private static func friendlyMessage(for error: Error, context: String) -> String {
        if let scanError = error as? FileScanError {
            switch scanError {
            case .cannotAccess:
                return L10n.Error.accessDenied(context)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
            return L10n.Error.permissionDenied(context)
        }
        return L10n.Error.generic(context, error.localizedDescription)
    }

    // MARK: - Selection

    /// Anchor used as the fixed end for Shift range-selection.
    public private(set) var selectionAnchor: URL?

    public func toggleSelection(_ url: URL, exclusive: Bool) {
        currentFileURL = url
        selectionAnchor = url
        if exclusive {
            selection = [url]
        } else if selection.contains(url) {
            selection.remove(url)
        } else {
            selection.insert(url)
        }
    }

    /// Shift-click: select the contiguous range (in displayed order) between the
    /// current anchor and `url`. With `additive` (Shift+⌘) the range is added to
    /// the existing selection; otherwise it replaces it.
    public func selectRange(to url: URL, additive: Bool) {
        let list = displayedFiles.map(\.url)
        guard let target = list.firstIndex(of: url) else { return }
        let anchorURL = selectionAnchor ?? currentFileURL
        let anchor = anchorURL.flatMap { list.firstIndex(of: $0) } ?? target
        let lo = min(anchor, target), hi = max(anchor, target)
        let range = Set(list[lo...hi])
        selection = additive ? selection.union(range) : range
        currentFileURL = url
    }

    /// Replaces the selection from a marquee drag, optionally keeping a base set
    /// (used when the drag started with ⌘ held to extend the existing selection).
    public func setMarqueeSelection(_ urls: Set<URL>, base: Set<URL>) {
        selection = base.union(urls)
        if let first = urls.first { currentFileURL = first }
    }

    /// Files after applying search / filter / sort. Drives the grid and the
    /// preview navigation order.
    public var displayedFiles: [MediaFile] {
        var result = files

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }

        switch formatFilter {
        case .all: break
        case .raw: result = result.filter { $0.isRAW }
        case .jpg: result = result.filter { MediaCatalog.jpegExtensions.contains($0.ext) }
        case .paired: result = result.filter { pairing.isPaired($0.url) }
        case .unpaired: result = result.filter { !pairing.isPaired($0.url) }
        }

        if minRating > 0 {
            result = result.filter { mark(for: $0).rating.stars >= minRating }
        }
        if let label = labelFilter {
            result = result.filter { mark(for: $0).label == label }
        }

        result.sort { lhs, rhs in
            switch sortKey {
            case .date:
                let l = lhs.modificationDate ?? .distantPast
                let r = rhs.modificationDate ?? .distantPast
                return sortAscending ? l < r : l > r
            case .name:
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return sortAscending ? order == .orderedAscending : order == .orderedDescending
            case .size:
                let l = lhs.fileSize ?? 0
                let r = rhs.fileSize ?? 0
                return sortAscending ? l < r : l > r
            }
        }
        return result
    }

    public var hasActiveFilter: Bool {
        !searchText.isEmpty || formatFilter != .all || minRating > 0 || labelFilter != nil
    }

    public func clearFilters() {
        searchText = ""
        formatFilter = .all
        minRating = 0
        labelFilter = nil
    }

    public func selectAll() {
        selection = Set(displayedFiles.map { $0.url })
    }

    public func invertSelection() {
        let all = Set(displayedFiles.map { $0.url })
        selection = all.subtracting(selection)
    }

    public func clearSelection() {
        selection = []
    }

    // MARK: - Preview

    public var previewFile: MediaFile? {
        guard let url = previewURL else { return nil }
        return files.first { $0.url == url }
    }

    public func openPreview(_ url: URL) {
        previewURL = url
        currentFileURL = url
    }

    public func closePreview() {
        previewURL = nil
    }

    /// Moves the preview by `delta` (e.g. -1 / +1) within the displayed order.
    public func previewStep(_ delta: Int) {
        let list = displayedFiles
        guard let url = previewURL,
              let index = list.firstIndex(where: { $0.url == url }) else { return }
        let next = index + delta
        guard list.indices.contains(next) else { return }
        previewURL = list[next].url
        currentFileURL = list[next].url
    }

    private func nextPreviewURL(after url: URL, in oldFiles: [MediaFile], deleted: Set<URL>) -> URL? {
        guard let idx = oldFiles.firstIndex(where: { $0.url == url }) else { return nil }
        var forward = idx + 1
        while forward < oldFiles.count {
            if !deleted.contains(oldFiles[forward].url) { return oldFiles[forward].url }
            forward += 1
        }
        var backward = idx - 1
        while backward >= 0 {
            if !deleted.contains(oldFiles[backward].url) { return oldFiles[backward].url }
            backward -= 1
        }
        return nil
    }

    // MARK: - Editor (non-destructive)

    public var editorFile: MediaFile? {
        guard let url = editorURL else { return nil }
        return files.first { $0.url == url }
    }

    public func openEditor(_ url: URL) {
        editorURL = url
    }

    public func closeEditor() {
        editorURL = nil
    }

    /// Default output path: same folder as the source, `<base>-edited.<ext>`,
    /// disambiguated so we never overwrite an existing file (originals included).
    public func suggestedExportURL(for source: URL, format: ExportFormat) -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let ext = format.fileExtension
        var candidate = dir.appendingPathComponent("\(base)-edited.\(ext)")
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base)-edited-\(i).\(ext)")
            i += 1
        }
        return candidate
    }

    /// Renders the edit at full resolution and writes a NEW file. The original
    /// is never modified. Returns the written URL on success.
    @discardableResult
    public func exportEdited(
        source: URL,
        adjustments: ImageAdjustments,
        settings: ExportSettings,
        to destination: URL
    ) async -> URL? {
        isExporting = true
        defer { isExporting = false }
        do {
            try await processor.export(
                url: source,
                adjustments: adjustments,
                settings: settings,
                to: destination
            )
        } catch {
            errorMessage = L10n.Error.exportFailed(error.localizedDescription)
            return nil
        }
        ingestExported(destination)
        statusMessage = L10n.Status.exported(destination.lastPathComponent)
        return destination
    }

    /// If the exported file landed inside a currently-scanned card, add it to the
    /// grid and recompute pairing so it appears immediately.
    private func ingestExported(_ url: URL) {
        guard let volume = targetVolumes.first(where: { url.path.hasPrefix($0.url.path) }),
              !files.contains(where: { $0.url == url }) else { return }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        var file = MediaFile(
            url: url,
            fileSize: (values?.fileSize).map(Int64.init),
            modificationDate: values?.contentModificationDate
        )
        file.volumeID = volume.id
        file.volumeName = volume.name
        file.volumeURL = volume.url
        files.insert(file, at: 0)
        var rule = pairingRule
        rule.crossLocation = crossCardMode
        pairing = pairingEngine.computePairs(files, rule: rule)
    }

    // MARK: - File actions (Finder / open / clipboard)

    public func revealInFinder(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    public func openWithDefaultApp(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #endif
    }

    /// Opens a web URL in the default browser.
    public func openExternalURL(_ string: String) {
        #if os(macOS)
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
        #endif
    }

    public func copyToClipboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    // MARK: - Pairing rule

    /// Switches the pairing preset and recomputes pairing on the current files
    /// (no rescan needed — all media extensions are already loaded).
    public func applyPairingRule(_ rule: PairingRule) {
        pairingRule = rule
        var r = rule
        r.crossLocation = crossCardMode
        pairing = pairingEngine.computePairs(files, rule: r)
        let pairedCount = files.filter { pairing.isPaired($0.url) }.count
        statusMessage = L10n.Status.pairingRule(rule.name, pairedCount)
    }

    // MARK: - Deletion

    public func planDeletion() -> DeletionPlan {
        planDeletion(for: selection)
    }

    public func planDeletion(for urls: Set<URL>) -> DeletionPlan {
        DeletionPlanner.plan(for: urls, pairing: pairing, allFiles: files)
    }

    /// Sets up and opens the delete confirmation for a context-menu/preview
    /// target: acts on the multi-selection if the target is part of it,
    /// otherwise on just the target.
    public func requestDelete(for url: URL) {
        if !(selection.contains(url) && selection.count > 1) {
            selection = [url]
            currentFileURL = url
        }
        isShowingDeleteSheet = true
    }

    /// Batched, non-blocking deletion. Moves run off-main in chunks while
    /// progress is published back to the UI. Works across cards in cross-card
    /// mode (the plan already contains paired files from other volumes).
    ///
    /// - Parameter permanent: when true, files are deleted directly (not moved
    ///   to Trash) and cannot be undone.
    public func performDeletion(_ plan: DeletionPlan, permanent: Bool = false) async {
        guard !plan.isEmpty else { return }

        // In single-card mode, guard against the card being removed after the
        // plan was built. In cross-card mode, per-file failures are tolerated.
        if !crossCardMode {
            guard let volume = selectedVolume,
                  FileManager.default.fileExists(atPath: volume.url.path) else {
                errorMessage = L10n.Error.cardRemovedCancelDelete
                return
            }
        }

        let trash = self.trash
        let urls = plan.urls
        isDeleting = true
        deletionTotal = urls.count
        deletionDone = 0

        var deleted = Set<URL>()
        var deletedItems: [DeletedItem] = []
        var failures: [String] = []

        for chunk in urls.chunked(into: 50) {
            let result = await Task.detached(priority: .userInitiated) { () -> ([(URL, URL?)], [String]) in
                var ok: [(URL, URL?)] = []
                var fail: [String] = []
                for url in chunk {
                    do {
                        if permanent {
                            try FileManager.default.removeItem(at: url)
                            ok.append((url, nil))
                        } else {
                            let trashedURL = try trash.moveToTrash(url)
                            ok.append((url, trashedURL))
                        }
                    } catch {
                        fail.append(url.lastPathComponent)
                    }
                }
                return (ok, fail)
            }.value

            for (original, trashed) in result.0 {
                deleted.insert(original)
                deletedItems.append(DeletedItem(original: original, trashed: trashed))
            }
            failures.append(contentsOf: result.1)
            deletionDone = deleted.count + failures.count
        }

        let oldDisplayed = displayedFiles
        files.removeAll { deleted.contains($0.url) }
        selection.removeAll()
        if let current = currentFileURL, deleted.contains(current) {
            currentFileURL = nil
        }
        // Keep the preview viewer usable: advance to the next surviving file, or
        // close it if everything around was deleted.
        if let preview = previewURL, deleted.contains(preview) {
            previewURL = nextPreviewURL(after: preview, in: oldDisplayed, deleted: deleted)
        }
        var rule = pairingRule
        rule.crossLocation = crossCardMode
        pairing = pairingEngine.computePairs(files, rule: rule)
        isDeleting = false

        if permanent {
            lastDeletedItems = []
            canUndo = false
            statusMessage = L10n.Status.permanentlyDeleted(deleted.count)
        } else {
            lastDeletedItems = deletedItems
            canUndo = deletedItems.contains { $0.trashed != nil }
            statusMessage = L10n.Status.movedToTrash(deleted.count)
        }

        if !failures.isEmpty {
            let shown = failures.prefix(5).joined(separator: ", ")
            let extra = failures.count > 5 ? L10n.Error.andMoreCount(failures.count) : ""
            let verb = permanent ? L10n.Error.verbDelete : L10n.Error.verbTrash
            errorMessage = L10n.Error.partialDelete(failures.count, verb, shown, extra)
        }
    }

    /// Restores the most recently deleted batch from the Trash.
    public func undoLastDeletion() {
        guard canUndo, !lastDeletedItems.isEmpty else { return }
        let items = lastDeletedItems
        lastDeletedItems = []
        canUndo = false

        var restored = 0
        var failed = 0
        for item in items {
            guard let trashed = item.trashed else { failed += 1; continue }
            do {
                try trash.restoreItem(at: trashed, to: item.original)
                restored += 1
            } catch {
                failed += 1
            }
        }

        statusMessage = L10n.Status.restored(restored)
        if failed > 0 {
            errorMessage = L10n.Error.restoreFailed(failed)
        }
        rescanCurrentScope()
    }

    // MARK: - Marks

    private func markKey(for file: MediaFile) -> String? {
        guard let vid = file.volumeID, let vurl = file.volumeURL else { return nil }
        return LibraryStore.key(volumeID: vid, fileURL: file.url, volumeURL: vurl)
    }

    public func mark(for file: MediaFile) -> FileMark {
        guard let key = markKey(for: file) else { return FileMark() }
        return marks[key] ?? library.mark(forKey: key)
    }

    public func setRating(_ rating: Rating, for file: MediaFile) {
        guard let key = markKey(for: file) else { return }
        var m = mark(for: file)
        m.rating = rating
        library.setMark(m, forKey: key)
        marks[key] = m
    }

    public func setLabel(_ label: ColorLabel, for file: MediaFile) {
        guard let key = markKey(for: file) else { return }
        var m = mark(for: file)
        m.label = label
        library.setMark(m, forKey: key)
        marks[key] = m
    }

    public func setRatingForSelection(_ rating: Rating) {
        for file in files where selection.contains(file.url) {
            setRating(rating, for: file)
        }
    }

    public func setLabelForSelection(_ label: ColorLabel) {
        for file in files where selection.contains(file.url) {
            setLabel(label, for: file)
        }
    }
}
