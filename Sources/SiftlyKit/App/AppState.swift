import Foundation
import Combine
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

/// Central observable application state. Wires together the platform services,
/// disk scanning, pairing, and user marks. UI observes this object.
/// Filter for the grid by file kind / pairing state.
public enum FormatFilter: String, CaseIterable, Identifiable, Sendable {
    case all, raw, jpg, video, paired, unpaired
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .all: return L10n.formatAll
        case .raw: return L10n.formatRAW
        case .jpg: return L10n.formatJPG
        case .video: return L10n.formatVideo
        case .paired: return L10n.formatPaired
        case .unpaired: return L10n.formatUnpaired
        }
    }
}

/// Sort key for the grid.
public enum SortKey: String, CaseIterable, Identifiable, Sendable {
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

/// What an import run should act on.
public enum ImportScope: String, Identifiable, Sendable {
    case selection, allShown
    public var id: String { rawValue }
    public var isSelectionOnly: Bool { self == .selection }
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
    private let library: LibraryStore
    private let defaults: UserDefaults
    private var terminationObserver: NSObjectProtocol?
    private let sidecarQueue = DispatchQueue(label: "com.siftly.sidecars", qos: .utility)
    /// Non-destructive image editor backend (Core Image).
    public let processor = ImageProcessor()

    // Published state
    @Published public private(set) var volumes: [Volume] = []
    /// Either a volume id, `allCardsTag`, or nil.
    @Published public var browseSelection: String?
    @Published public private(set) var files: [MediaFile] = [] {
        didSet { if !appendingFiles { rebuildFileIndex() }; recomputeDisplayed() }
    }
    /// `files` keyed by URL, so preview/editor/deletion lookups are O(1)
    /// instead of a linear scan on every SwiftUI body evaluation.
    private var appendingFiles = false
    private var filesByURL: [URL: MediaFile] = [:]
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
    /// Drives the import sheet; true when it should act on the selection only.
    @Published public var importScope: ImportScope?
    @Published public var pairingRule: PairingRule = .default
    @Published public private(set) var pairing: PairingResult = .empty {
        didSet { recomputeDisplayed() }
    }

    // Filter / sort / search state for the grid.
    @Published public var searchText: String = "" { didSet { recomputeDisplayed() } }
    @Published public var formatFilter: FormatFilter = .all { didSet { recomputeDisplayed() } }
    @Published public var minRating: Int = 0 { didSet { recomputeDisplayed() } }
    @Published public var labelFilter: ColorLabel? { didSet { recomputeDisplayed() } }
    @Published public var sortKey: SortKey = .date { didSet { recomputeDisplayed() } }
    @Published public var sortAscending: Bool = false { didSet { recomputeDisplayed() } }
    @Published public private(set) var isScanning = false
    @Published public var statusMessage: String = L10n.Status.noCards
    /// User-facing error, surfaced as an alert. Cleared when dismissed.
    @Published public var errorMessage: String?
    /// Marks keyed by `volumeID::relativePath`, mirrored for SwiftUI updates.
    @Published public private(set) var marks: [String: FileMark] = [:] {
        didSet {
            // Only rating/label filters read marks; skip the rebuild otherwise.
            if minRating > 0 || labelFilter != nil { recomputeDisplayed() }
        }
    }

    // Import progress.
    @Published public private(set) var isImporting = false
    @Published public private(set) var importedCount = 0
    @Published public private(set) var importTotalCount = 0
    @Published public private(set) var importedBytes: Int64 = 0
    @Published public private(set) var importTotalBytes: Int64 = 0
    @Published public private(set) var importCurrentName: String = ""
    /// Files that failed to copy or verify, shown after the run.
    @Published public private(set) var importFailures: [String] = []
    private var importTask: Task<ImportOutcome, Never>?

    public var importProgress: Double {
        importTotalBytes == 0 ? 0 : Double(importedBytes) / Double(importTotalBytes)
    }

    /// Persisted import preferences (destination is stored as a bookmark so it
    /// survives renames and keeps the user's granted access).
    private static let importDestinationKey = "siftly.import.destination"
    private static let importOrganizationKey = "siftly.import.organization"

    @Published public var importSettings = ImportSettings() {
        didSet { persistImportSettings() }
    }

    private func persistImportSettings() {
        defaults.set(
            importSettings.organization.rawValue, forKey: Self.importOrganizationKey
        )
        if let destination = importSettings.destination,
           let bookmark = try? destination.bookmarkData(
               options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
           ) {
            defaults.set(bookmark, forKey: Self.importDestinationKey)
        }
    }

    private func restoreImportSettings() {
        var restored = ImportSettings()
        if let raw = defaults.string(forKey: Self.importOrganizationKey),
           let organization = ImportOrganization(rawValue: raw) {
            restored.organization = organization
        }
        if let bookmark = defaults.data(forKey: Self.importDestinationKey) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), !stale {
                restored.destination = url
            }
        }
        // Assigned directly to avoid the didSet writing back what we just read.
        _importSettings = Published(initialValue: restored)
    }

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

    // Undo support for the most recent deletion. The file's mark travels with
    // it: deletion prunes the mark index, so undo has to be able to put it back.
    private struct DeletedItem {
        let original: URL
        let trashed: URL?
        let markKey: String?
        let mark: FileMark?
    }
    private var lastDeletedItems: [DeletedItem] = []
    @Published public private(set) var canUndo = false

    // User preferences (persisted in UserDefaults).
    private static let prefetchKey = "siftly.preview.prefetchCount"
    /// How many neighbors (per side) to preload around the viewed photo. 0 = off.
    @Published public var previewPrefetchCount: Int {
        didSet {
            let clamped = max(0, min(previewPrefetchCount, 20))
            if clamped != previewPrefetchCount { previewPrefetchCount = clamped; return }
            defaults.set(previewPrefetchCount, forKey: Self.prefetchKey)
            thumbnails.configurePreviewCache(count: previewPrefetchCount)
        }
    }

    private static let xmpKey = "siftly.writeXMPSidecars"
    /// When on, every rating/label change also writes an Adobe-style `.xmp`
    /// sidecar next to the original, so a cull can be handed to Lightroom /
    /// Capture One. Off by default: it writes to the user's card, which may be
    /// full or read-only, and Siftly's own index works without it.
    @Published public var writesXMPSidecars: Bool {
        didSet { defaults.set(writesXMPSidecars, forKey: Self.xmpKey) }
    }

    private static let languageKey = "siftly.languageOverride"
    /// Selected interface language: `nil` (or "system") follows the OS; otherwise
    /// a locale identifier like "en" or "zh-Hans".
    @Published public var languageOverride: String? {
        didSet {
            defaults.set(languageOverride, forKey: Self.languageKey)
            L10n.overrideLocaleIdentifier = languageOverride
        }
    }

    /// Locales the UI offers an explicit choice for (besides "follow system").
    public static let supportedLanguages: [String] = ["en", "zh-Hans"]

    /// Size requested for the full-size preview, in **points** — the unit
    /// `ThumbnailService` takes, since it applies the Retina scale itself.
    /// Passing pixels here silently doubled the request: a "2600px" preview was
    /// decoding at 5200x5200, about 108 MB per image.
    ///
    /// Derived from the actual display rather than a constant, so a laptop
    /// doesn't pay for a 6K panel and a 6K panel isn't served a soft preview.
    /// The 1.3x margin leaves some headroom for moderate zoom.
    public static var previewPointSize: CGSize {
        #if canImport(AppKit)
        let longestEdge = NSScreen.main.map { max($0.frame.width, $0.frame.height) } ?? 1600
        let points = min(max(longestEdge * 1.3, 1200), 2200)
        return CGSize(width: points, height: points)
        #else
        return CGSize(width: 1600, height: 1600)
        #endif
    }

    public init(
        volumeService: VolumeService? = nil,
        fileSystem: FileSystemService? = nil,
        trash: TrashService? = nil,
        thumbnails: ThumbnailProvider? = nil,
        library: LibraryStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.library = library ?? LibraryStore()
        let storedPrefetch = defaults.object(forKey: Self.prefetchKey) as? Int
        self.previewPrefetchCount = storedPrefetch ?? 3
        self.writesXMPSidecars = defaults.bool(forKey: Self.xmpKey)
        let storedLanguage = defaults.string(forKey: Self.languageKey)
        self.languageOverride = storedLanguage
        L10n.overrideLocaleIdentifier = storedLanguage

        #if os(macOS)
        self.volumeService = volumeService ?? MacVolumeService()
        self.fileSystem = fileSystem ?? MacFileSystemService()
        self.trash = trash ?? MacTrashService()
        self.thumbnails = thumbnails ?? ThumbnailProvider(service: MacThumbnailService())
        #elseif os(Windows)
        self.volumeService = WindowsVolumeService()
        self.fileSystem = WindowsFileSystemService()
        self.trash = WindowsTrashService()
        self.thumbnails = ThumbnailProvider(service: WindowsThumbnailService())
        #endif

        self.thumbnails.configurePreviewCache(count: previewPrefetchCount)
        restoreImportSettings()
        self.library.onSaveError = { [weak self] error in
            Task { @MainActor in self?.errorMessage = error.localizedDescription }
        }
        #if canImport(AppKit)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPersistence() }
        }
        #endif

        self.volumeService.startObserving { [weak self] in
            self?.refreshVolumes()
        }
        refreshVolumes()
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    /// Preloads the photos adjacent to `url` (per the user's prefetch setting) so
    /// flipping to the next/previous photo in the viewer is instant.
    public func prefetchAdjacentPreviews(around url: URL) {
        let n = previewPrefetchCount
        guard n > 0 else { return }
        let list = displayedFiles
        guard let idx = displayedIndex[url] else { return }
        var urls: [URL] = []
        for step in 1...n {
            if idx + step < list.count { urls.append(list[idx + step].url) }
            if idx - step >= 0 { urls.append(list[idx - step].url) }
        }
        thumbnails.prefetchPreviews(urls, pointSize: Self.previewPointSize)
    }

    /// True when browsing/merging all cards (enables cross-card pairing).
    public var crossCardMode: Bool { browseSelection == Self.allCardsTag }

    public var selectedVolume: Volume? {
        guard let id = browseSelection, id != Self.allCardsTag else { return nil }
        return volumes.first { $0.id == id }
    }

    /// True when the delete target lives on a removable card, where the Trash
    /// is a folder *on the card* and so frees no space until it is emptied.
    public var selectedVolumeIsRemovable: Bool {
        if crossCardMode { return volumes.contains { $0.isRemovable } }
        return selectedVolume?.isRemovable ?? false
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
        let changed = current.map(\.id) != volumes.map(\.id)
        volumes = current

        if crossCardMode {
            if current.isEmpty {
                scanTask?.cancel()
                resetBrowseState(message: L10n.Status.noCards)
                browseSelection = nil
            } else if changed {
                // Re-merge across the (changed) set of cards. Guarded on an
                // actual change: mount/unmount/rename notifications also fire
                // for unrelated volumes (disk images, backups), and restarting
                // the scan for those would throw away an in-progress one.
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
        let extensions = rule.allExtensions.union(MediaCatalog.allMediaExtensions)
        let fs = fileSystem
        let scopeName = crossCardMode ? L10n.allStorageCards : (vols.first?.name ?? "")
        statusMessage = L10n.Status.scanning(scopeName)

        scanTask = Task { [weak self] in
            // Stream batches (off-main) from each target volume, stamping the
            // owning volume so cross-card pairing and mark keys work.
            // `abandoned` lets the producer bail out of the directory walk. The
            // detached task is not a child of `scanTask`, so cancelling the
            // consumer alone would leave it enumerating the rest of the card
            // (potentially 100k+ files) into an unbounded stream buffer.
            let abandoned = ScanFlag()
            let stream = AsyncThrowingStream<[MediaFile], Error> { continuation in
                continuation.onTermination = { _ in abandoned.cancel() }
                Task.detached(priority: .userInitiated) {
                    do {
                        var pending: [MediaFile] = []
                        var lastPublish = Date.distantPast
                        for vol in vols {
                            if abandoned.isCancelled { break }
                            try fs.scanMediaFiles(in: vol.url, extensions: extensions, batchSize: 256) { batch in
                                if abandoned.isCancelled { return false }
                                let stamped = batch.map { file -> MediaFile in
                                    var m = file
                                    m.volumeID = vol.id
                                    m.volumeName = vol.name
                                    m.volumeURL = vol.url
                                    return m
                                }
                                pending.append(contentsOf: stamped)
                                if Date().timeIntervalSince(lastPublish) >= 0.15 {
                                    continuation.yield(pending)
                                    pending.removeAll(keepingCapacity: true)
                                    lastPublish = Date()
                                }
                                return true
                            }
                        }
                        if !pending.isEmpty, !abandoned.isCancelled { continuation.yield(pending) }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            do {
                for try await batch in stream {
                    if Task.isCancelled { return }
                    guard let self, self.scanID == token else { return }
                    self.appendScanned(batch)
                    self.statusMessage = L10n.Status.scanningFound(self.files.count)
                }

                if Task.isCancelled { return }
                guard let self, self.scanID == token else { return }
                let snapshot = self.files
                var currentRule = self.pairingRule
                currentRule.crossLocation = self.crossCardMode
                let completedRule = currentRule
                let pairs = await Task.detached(priority: .userInitiated) {
                    PairingEngine().computePairs(snapshot, rule: completedRule)
                }.value
                guard !Task.isCancelled, self.scanID == token else { return }
                self.pairing = pairs
                await self.displayTask?.value
                guard !Task.isCancelled, self.scanID == token else { return }
                self.isScanning = false
                let pairedCount = snapshot.filter { pairs.isPaired($0.url) }.count
                if self.crossCardMode {
                    self.statusMessage = L10n.Status.multiCardSummary(vols.count, snapshot.count, pairedCount)
                } else {
                    self.statusMessage = L10n.Status.fileCount(snapshot.count)
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
        guard let target = displayedIndex[url] else { return }
        let anchorURL = selectionAnchor ?? currentFileURL
        let anchor = anchorURL.flatMap { displayedIndex[$0] } ?? target
        let lo = min(anchor, target), hi = max(anchor, target)
        let range = Set(displayedFiles[lo...hi].map(\.url))
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
    ///
    /// Cached rather than computed: SwiftUI reads this many times per body
    /// evaluation (the grid alone touches it five times), and the preview viewer
    /// re-evaluates on every pan/zoom frame. Recomputing meant a full filter +
    /// `localizedStandardCompare` sort of the whole card dozens of times per
    /// second. It is now rebuilt only when an input actually changes.
    @Published public private(set) var displayedFiles: [MediaFile] = []

    /// Position of each displayed file, for O(1) navigation lookups.
    private var displayedIndex: [URL: Int] = [:]

    /// Index of `url` in the displayed order, or nil when it is filtered out.
    public func displayedPosition(of url: URL) -> Int? { displayedIndex[url] }

    /// The loaded file for `url`, in O(1). Views call this on every body
    /// evaluation, so it must not scan `files`.
    public func file(for url: URL) -> MediaFile? { filesByURL[url] }

    private func rebuildFileIndex() {
        filesByURL = Dictionary(files.map { ($0.url, $0) }, uniquingKeysWith: { _, b in b })
    }

    private let displayQueue = DispatchQueue(label: "com.siftly.display", qos: .userInitiated)
    private var displayTask: Task<Void, Never>?
    private var displayRevision = UUID()

    private func recomputeDisplayed() {
        displayRevision = UUID()
        displayTask?.cancel()
        if files.isEmpty {
            displayedFiles = []
            displayedIndex = [:]
            return
        }
        let revision = displayRevision
        displayTask = Task { [weak self] in
            // Coalesce scan batches, search keystrokes and related filter changes.
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled, let self else { return }
            let query = DisplayQuery(
                files: self.files, searchText: self.searchText, formatFilter: self.formatFilter,
                minRating: self.minRating, labelFilter: self.labelFilter,
                sortKey: self.sortKey, sortAscending: self.sortAscending,
                pairing: self.pairing, marks: self.library.snapshot
            )
            let cancelled = ScanFlag()
            let result = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    self.displayQueue.async {
                        guard !cancelled.isCancelled else {
                            continuation.resume(returning: Optional<(files: [MediaFile], index: [URL: Int])>.none)
                            return
                        }
                        continuation.resume(returning: query.evaluate())
                    }
                }
            } onCancel: { cancelled.cancel() }
            guard !Task.isCancelled, self.displayRevision == revision, let result else { return }
            self.displayedIndex = result.index
            self.displayedFiles = result.files
        }
    }

    private func appendScanned(_ batch: [MediaFile]) {
        for file in batch { filesByURL[file.url] = file }
        appendingFiles = true
        files.append(contentsOf: batch)
        appendingFiles = false
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
        return filesByURL[url]
    }

    public func openPreview(_ url: URL) {
        previewURL = url
        currentFileURL = url
    }

    public func closePreview() {
        thumbnails.cancelPrefetches()
        previewURL = nil
    }

    /// Moves the preview by `delta` (e.g. -1 / +1) within the displayed order.
    public func previewStep(_ delta: Int) {
        guard let url = previewURL, let index = displayedIndex[url] else { return }
        let next = index + delta
        guard displayedFiles.indices.contains(next) else { return }
        previewURL = displayedFiles[next].url
        currentFileURL = displayedFiles[next].url
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
        return filesByURL[url]
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
              filesByURL[url] == nil else { return }
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
        DeletionPlanner.plan(for: urls, pairing: pairing, filesByURL: filesByURL)
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
        let metadata = Dictionary(plan.allFiles.compactMap { file -> (URL, (String, FileMark))? in
            guard let key = markKey(for: file) else { return nil }
            return (file.url, (key, mark(for: file)))
        }, uniquingKeysWith: { first, _ in first })
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
                let saved = metadata[original]
                deletedItems.append(
                    DeletedItem(
                        original: original,
                        trashed: trashed,
                        markKey: saved?.0,
                        mark: saved?.1
                    )
                )
            }
            failures.append(contentsOf: result.1)
            deletionDone = deleted.count + failures.count
        }

        let oldDisplayed = displayedFiles
        // Drop the persisted ratings/labels of the removed files. Cameras reuse
        // file names after a counter reset, so a stale mark would otherwise
        // reattach itself to an unrelated photo later on. Undo restores them
        // (they are carried on `DeletedItem`).
        //
        // Only keys that actually carry a mark: otherwise every deletion would
        // copy and republish the whole index — and, with a rating/label filter
        // active, trigger a pointless full re-sort.
        let staleKeys = deletedItems.filter { $0.mark?.isEmpty == false }.compactMap(\.markKey)
        files.removeAll { deleted.contains($0.url) }
        if !staleKeys.isEmpty {
            var remaining = marks
            for key in staleKeys { remaining.removeValue(forKey: key) }
            marks = remaining        // one publish, not one per file
            library.removeMarks(forKeys: staleKeys)
        }
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
        var revivedMarks: [String: FileMark] = [:]
        for item in items {
            guard let trashed = item.trashed else { failed += 1; continue }
            do {
                try trash.restoreItem(at: trashed, to: item.original)
                restored += 1
                // Put the file's rating/label back too — deletion pruned it.
                if let key = item.markKey, let mark = item.mark, !mark.isEmpty {
                    revivedMarks[key] = mark
                }
            } catch {
                failed += 1
            }
        }
        if !revivedMarks.isEmpty {
            library.setMarks(revivedMarks)
            marks.merge(revivedMarks) { _, new in new }
        }

        statusMessage = L10n.Status.restored(restored)
        if failed > 0 {
            errorMessage = L10n.Error.restoreFailed(failed)
        }
        rescanCurrentScope()
    }

    // MARK: - Import

    /// Files an import would act on: the selection when there is one, otherwise
    /// everything currently shown. Paired companions are pulled in when the
    /// setting is on, so a RAW is never imported without its JPG.
    public func importCandidates(selectionOnly: Bool) -> [MediaFile] {
        let base = selectionOnly
            ? displayedFiles.filter { selection.contains($0.url) }
            : displayedFiles
        guard importSettings.includesPairedFiles else { return base }

        var seen = Set(base.map(\.url))
        var result = base
        for file in base {
            for partner in pairing.partners(of: file.url)
            where !seen.contains(partner) {
                if let partnerFile = filesByURL[partner] {
                    result.append(partnerFile)
                    seen.insert(partner)
                }
            }
        }
        return result
    }

    /// Builds the copy plan, consulting the destination for files already there.
    ///
    /// Off the main actor: planning stats every candidate against the
    /// destination, which is thousands of synchronous filesystem calls on a full
    /// card and would visibly hang the sheet.
    public func planImport(selectionOnly: Bool) async -> ImportPlan {
        let candidates = importCandidates(selectionOnly: selectionOnly)
        let settings = importSettings
        let work = Task.detached(priority: .userInitiated) {
            ImportPlanner.plan(for: candidates, settings: settings) { url in
                (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init)
            }
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    public func cancelImport() {
        importTask?.cancel()
    }

    /// Copies the planned files to the destination, verifying and optionally
    /// clearing the originals afterwards. Runs off the main actor in a
    /// cancellable task; progress is published back for the sheet.
    public func performImport(_ plan: ImportPlan) async {
        let settings = importSettings
        guard !isImporting, !plan.isEmpty, let destination = settings.destination else { return }
        if let planned = plan.settings, !planned.hasSamePlanningInputs(as: settings) { return }

        // Fail before copying anything rather than filling the disk and dying
        // half way through.
        if let free = FileCopier.availableCapacity(at: destination), free < plan.totalBytes {
            errorMessage = ImportError.notEnoughSpace(
                needed: plan.totalBytes, available: free
            ).localizedDescription
            return
        }

        isImporting = true
        importedCount = 0
        importTotalCount = plan.count
        importedBytes = 0
        importTotalBytes = plan.totalBytes
        importFailures = []
        importCurrentName = ""

        let verifies = settings.requiresVerification
        // Held directly (not wrapped in another task) so `cancelImport()`
        // actually reaches the copy loop.
        let work = Task { [weak self] () -> ImportOutcome in
            await Self.run(plan, verifies: verifies) { update in
                await MainActor.run { self?.apply(update) }
            }
        }
        importTask = work
        let outcome = await work.value
        importTask = nil

        isImporting = false
        importCurrentName = ""
        importFailures = outcome.failures

        if outcome.cancelled {
            statusMessage = L10n.Status.importCancelled(outcome.copied.count)
        } else {
            let copiedBytes = outcome.copied.compactMap { $0.source.fileSize }.reduce(0, +)
            statusMessage = L10n.Status.imported(
                outcome.copied.count,
                ByteCountFormatter.string(fromByteCount: copiedBytes, countStyle: .file)
            )
        }
        if !outcome.failures.isEmpty {
            let shown = outcome.failures.prefix(5).joined(separator: ", ")
            errorMessage = L10n.Error.importPartial(outcome.failures.count, shown)
        }

        // Only ever clear originals that were copied *and* verified.
        if settings.deletesAfterImport, verifies, !outcome.copied.isEmpty {
            let safeToRemove = Set(outcome.copied.map { $0.source.url })
            await performDeletion(
                DeletionPlanner.plan(for: safeToRemove, pairing: .empty, filesByURL: filesByURL)
            )
        }
    }

    private struct ImportUpdate: Sendable {
        var name: String?
        var bytes: Int64 = 0
        var finishedFile = false
    }

    private struct ImportOutcome: Sendable {
        var copied: [ImportItem] = []
        var failures: [String] = []
        var cancelled = false
    }

    private func apply(_ update: ImportUpdate) {
        // Progress hops are fire-and-forget, so a straggler can land after the
        // run finished; ignore those rather than moving a dead progress bar.
        guard isImporting else { return }
        if let name = update.name { importCurrentName = name }
        importedBytes += update.bytes
        if update.finishedFile { importedCount += 1 }
    }

    /// The copy loop itself. Nonisolated so it runs off the main actor; it only
    /// talks back through `report`.
    /// Bytes copied between progress updates.
    private nonisolated static let progressReportInterval: Int64 = 16 * 1024 * 1024

    private nonisolated static func run(
        _ plan: ImportPlan,
        verifies: Bool,
        report: @escaping @Sendable (ImportUpdate) async -> Void
    ) async -> ImportOutcome {
        var outcome = ImportOutcome()

        for item in plan.items {
            if Task.isCancelled { outcome.cancelled = true; break }
            await report(ImportUpdate(name: item.source.name))

            do {
                // Progress is coalesced: reporting every 4 MB chunk would hop to
                // the main actor tens of thousands of times on a full card.
                var pending: Int64 = 0
                try FileCopier.copy(from: item.source.url, to: item.destination, verifies: verifies) { bytes in
                    if Task.isCancelled { return false }
                    pending += bytes
                    if pending >= Self.progressReportInterval {
                        let batch = pending
                        pending = 0
                        Task { await report(ImportUpdate(bytes: batch)) }
                    }
                    return true
                }
                if pending > 0 { await report(ImportUpdate(bytes: pending)) }
                outcome.copied.append(item)
                await report(ImportUpdate(finishedFile: true))
            } catch is CancellationError {
                outcome.cancelled = true
                break
            } catch {
                outcome.failures.append(item.source.name)
                await report(ImportUpdate(finishedFile: true))
            }
        }
        return outcome
    }

    public func flushPersistence() {
        do { try library.flush() }
        catch { errorMessage = error.localizedDescription }
        sidecarQueue.sync {}
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
        updateMark(for: file) { $0.rating = rating }
    }

    public func setLabel(_ label: ColorLabel, for file: MediaFile) {
        updateMark(for: file) { $0.label = label }
    }

    /// The saved editor state for a file, or identity when it has never been
    /// edited.
    public func adjustments(for file: MediaFile) -> ImageAdjustments {
        mark(for: file).adjustments ?? .identity
    }

    /// Persists (or clears) the non-destructive edit for a file.
    public func setAdjustments(_ adjustments: ImageAdjustments, for file: MediaFile) {
        updateMark(for: file) { $0.adjustments = adjustments.isIdentity ? nil : adjustments }
    }

    private func updateMark(for file: MediaFile, _ edit: (inout FileMark) -> Void) {
        guard let key = markKey(for: file) else { return }
        var m = mark(for: file)
        let previous = m
        edit(&m)
        library.setMark(m, forKey: key)
        if m.isEmpty { marks.removeValue(forKey: key) } else { marks[key] = m }
        if previous.rating != m.rating || previous.label != m.label {
            writeSidecar(m, for: file.url)
        }
    }

    /// Mirrors a mark into an XMP sidecar when the preference is on. Fire and
    /// forget off the main actor: the card can be slow, and a sidecar failure
    /// must never block or fail the in-app mark.
    private func writeSidecar(_ mark: FileMark, for url: URL) {
        guard writesXMPSidecars else { return }
        sidecarQueue.async { [weak self] in
            do { try XMPSidecar.write(mark, for: url) }
            catch {
                Task { @MainActor in self?.errorMessage = L10n.Error.xmpWriteFailed(1) }
            }
        }
    }

    /// Reads XMP sidecars for every loaded file and adopts any rating/label
    /// found. Explicit rather than automatic: doing it during a scan would add
    /// a stat plus a parse per file to the slowest part of the app.
    /// Existing Siftly marks win, so this never overwrites local work.
    public func importXMPSidecars() async {
        let candidates = files.filter { mark(for: $0).isEmpty }
        guard !candidates.isEmpty else {
            statusMessage = L10n.Status.xmpImported(0)
            return
        }
        let urls = candidates.map(\.url)
        let found = await Task.detached(priority: .userInitiated) { () -> [URL: FileMark] in
            var result: [URL: FileMark] = [:]
            for url in urls {
                if let mark = XMPSidecar.read(for: url) { result[url] = mark }
            }
            return result
        }.value

        var updates: [String: FileMark] = [:]
        for (url, mark) in found {
            guard let file = filesByURL[url], self.mark(for: file).isEmpty,
                  let key = markKey(for: file) else { continue }
            updates[key] = mark
        }
        if !updates.isEmpty {
            library.setMarks(updates)
            marks.merge(updates) { _, new in new }
        }
        statusMessage = L10n.Status.xmpImported(updates.count)
    }

    /// Writes sidecars for every currently marked file in one pass, so an
    /// existing cull can be exported without re-touching each photo.
    public func exportAllXMPSidecars() async {
        let marked = files.compactMap { file -> (URL, FileMark)? in
            let m = mark(for: file)
            return m.isEmpty ? nil : (file.url, m)
        }
        guard !marked.isEmpty else {
            statusMessage = L10n.Status.xmpExported(0)
            return
        }
        let failures = await withCheckedContinuation { continuation in
            sidecarQueue.async {
                var failed = 0
                for (url, mark) in marked {
                    do { try XMPSidecar.write(mark, for: url) } catch { failed += 1 }
                }
                continuation.resume(returning: failed)
            }
        }
        statusMessage = L10n.Status.xmpExported(marked.count - failures)
        if failures > 0 {
            errorMessage = L10n.Error.xmpWriteFailed(failures)
        }
    }

    public func setRatingForSelection(_ rating: Rating) {
        applyToSelection { $0.rating = rating }
    }

    public func setLabelForSelection(_ label: ColorLabel) {
        applyToSelection { $0.label = label }
    }

    /// Applies a mark edit across the selection with a single index write.
    /// Doing this per file would re-encode and re-write the whole mark index
    /// once per photo — hundreds of full disk writes for one batch command.
    private func applyToSelection(_ edit: (inout FileMark) -> Void) {
        var updates: [String: FileMark] = [:]
        for url in selection.sorted(by: { $0.path < $1.path }) {
            guard let file = filesByURL[url], let key = markKey(for: file) else { continue }
            var m = mark(for: file)
            edit(&m)
            updates[key] = m
            writeSidecar(m, for: url)
        }
        guard !updates.isEmpty else { return }
        library.setMarks(updates)
        var merged = marks
        for (key, m) in updates {
            // Clearing a rating/label drops the entry rather than storing an
            // empty mark, matching what the store persists.
            if m.isEmpty { merged.removeValue(forKey: key) } else { merged[key] = m }
        }
        marks = merged
    }
}
