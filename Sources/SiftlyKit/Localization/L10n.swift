import Foundation

/// Centralized user-facing strings. English is the development language; translations
/// live in `Resources/Localizable.xcstrings` (zh-Hans today, more locales later).
enum L10n {
    private static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = String(localized: String.LocalizationValue(key), bundle: .module)
        guard !args.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: args)
    }

    // MARK: - App / menus

    static var aboutSiftly: String { tr("About Siftly") }
    static var appName: String { tr("Siftly") }
    static var ok: String { tr("OK") }
    static var cancel: String { tr("Cancel") }
    static var done: String { tr("Done") }
    static var errorTitle: String { tr("Something went wrong") }

    // MARK: - Sidebar

    static var allStorageCards: String { tr("All Storage Cards") }
    static var allStorageCardsHelp: String {
        tr("Browse all cards together; pair and delete by filename across cards")
    }
    static var crossCardPairing: String { tr("Cross-Card Pairing") }
    static var storageCards: String { tr("Storage Cards") }
    static var noStorageCards: String { tr("No storage cards detected") }
    static var insertCardHint: String {
        tr("Insert an SD or CFexpress card, then click Refresh")
    }
    static var refreshHelp: String { tr("Refresh storage cards and file list") }

    // MARK: - Grid

    static var scanning: String { tr("Scanning…") }
    static var selectCardPrompt: String { tr("Select a storage card on the left") }
    static var noFilesToShow: String { tr("No files to display") }
    static var noMatchingFiles: String { tr("No matching files") }
    static var adjustFiltersHint: String { tr("Adjust or clear filters") }
    static func selectedCount(_ n: Int) -> String { tr("Selected %lld", n) }
    static var selectAllHelp: String { tr("Select all") }
    static var invertSelection: String { tr("Invert selection") }
    static var clearSelection: String { tr("Clear selection") }
    static var batchRating: String { tr("Batch rating") }
    static var clearRating: String { tr("Clear rating") }
    static var batchLabels: String { tr("Batch labels") }
    static var selectionAndBatchHelp: String { tr("Selection and batch marking") }
    static var pairingRulesHelp: String {
        tr("Pairing rules (Canon / Nikon / Fuji / Sony / Universal)")
    }
    static var moveToTrashHelp: String { tr("Move to Trash (includes paired files) · Delete") }
    static var undoDeleteHelp: String { tr("Undo last deletion (restore from Trash)") }
    static var thumbnailSize: String { tr("Thumbnail size") }
    static var searchFilename: String { tr("Search filename") }
    static var clearFilters: String { tr("Clear filters") }
    static func fileCount(_ shown: Int, _ total: Int) -> String { tr("%lld / %lld", shown, total) }
    static var all: String { tr("All") }
    static func starsAndAbove(_ stars: Int) -> String { tr("%@ and above", String(repeating: "★", count: stars)) }
    static var rating: String { tr("Rating") }
    static func ratingAtLeast(_ n: Int) -> String { tr("★%lld+", n) }
    static var label: String { tr("Label") }
    static func labelFilter(_ name: String) -> String { tr("Label: %@", name) }
    static var ascending: String { tr("Ascending") }
    static var sort: String { tr("Sort") }

    // MARK: - Filters / sort keys

    static var formatAll: String { tr("All") }
    static var formatRAW: String { tr("RAW") }
    static var formatJPG: String { tr("JPG") }
    static var formatPaired: String { tr("Paired") }
    static var formatUnpaired: String { tr("Unpaired") }
    static var sortDate: String { tr("Date modified") }
    static var sortName: String { tr("Filename") }
    static var sortSize: String { tr("File size") }

    // MARK: - Pairing rules

    static var pairingUniversal: String { tr("Universal RAW + JPG") }
    static var pairingSony: String { tr("Sony ARW + JPG") }
    static var pairingCanon: String { tr("Canon CR2/CR3 + JPG") }
    static var pairingNikon: String { tr("Nikon NEF/NRW + JPG") }
    static var pairingFuji: String { tr("Fuji RAF + JPG") }

    // MARK: - Color labels

    static var labelNone: String { tr("None") }
    static var labelRed: String { tr("Red") }
    static var labelOrange: String { tr("Orange") }
    static var labelYellow: String { tr("Yellow") }
    static var labelGreen: String { tr("Green") }
    static var labelBlue: String { tr("Blue") }
    static var labelPurple: String { tr("Purple") }
    static var labelGray: String { tr("Gray") }

    // MARK: - Inspector

    static var inspectorTitle: String { tr("Info") }
    static var noFileSelected: String { tr("No file selected") }
    static var size: String { tr("Size") }
    static var modified: String { tr("Modified") }
    static var format: String { tr("Format") }
    static var pairedWith: String { tr("Paired with") }
    static var marks: String { tr("Marks") }
    static var exif: String { tr("EXIF") }
    static var dimensions: String { tr("Dimensions") }
    static var camera: String { tr("Camera") }
    static var lens: String { tr("Lens") }
    static var iso: String { tr("ISO") }
    static var aperture: String { tr("Aperture") }
    static var shutter: String { tr("Shutter") }
    static var focalLength: String { tr("Focal length") }
    static var dateTaken: String { tr("Date taken") }
    static var noExif: String { tr("No EXIF data") }

    // MARK: - Thumbnail context menu

    static var openPreview: String { tr("Open preview") }
    static var editPhoto: String { tr("Edit…") }
    static var revealInFinder: String { tr("Reveal in Finder") }
    static var openWithDefaultApp: String { tr("Open with default app") }
    static var copyFilename: String { tr("Copy filename") }
    static var copyPath: String { tr("Copy path") }
    static var moveToTrash: String { tr("Move to Trash") }

    // MARK: - Preview

    static func deleteConfirmTitle(_ name: String) -> String { tr("Delete “%@”?", name) }
    static var deletePermanent: String { tr("Delete permanently") }
    static var deletePermanentPreview: String { tr("Delete permanently (cannot undo)") }
    static var deleteWithPairingUndo: String {
        tr("Paired files will also be deleted. Press ⌘Z to undo.")
    }
    static var deleteUndoHint: String { tr("Press ⌘Z to undo.") }
    static var hasPairing: String { tr("Paired") }
    static var closeHelp: String { tr("Close (Esc)") }
    static var fit: String { tr("Fit") }
    static var photoInfo: String { tr("Photo info") }
    static var togglePhotoInfoHelp: String { tr("Show/hide photo info (I)") }
    static var edit: String { tr("Edit") }
    static var moveToTrashDeleteHelp: String { tr("Move to Trash · Delete") }
    static var captured: String { tr("Captured") }
    static var exposure: String { tr("Exposure") }
    static var loadingExif: String { tr("Loading…") }

    // MARK: - Delete sheet

    static var confirmDelete: String { tr("Confirm deletion") }
    static func deletePlanBody(_ count: Int, _ size: String, _ permanent: Bool) -> String {
        if permanent {
            return tr("%lld files will be permanently deleted (%@). Paired files are included.", count, size)
        }
        return tr("%lld files will be moved to Trash (%@). Paired files are included.", count, size)
    }
    static var crossCardWarning: String {
        tr("Cross-card mode pairs by filename. Verify that files on different cards are truly the same photo (camera filenames can repeat).")
    }
    static func directlySelected(_ n: Int) -> String { tr("Selected (%lld)", n) }
    static func pairedAdditions(_ n: Int) -> String { tr("Paired additions (%lld)", n) }
    static var deleteDirectToggle: String {
        tr("Delete permanently (skip Trash, cannot undo)")
    }
    static func deletingProgress(_ done: Int, _ total: Int, _ permanent: Bool) -> String {
        if permanent {
            return tr("Deleting %lld/%lld", done, total)
        }
        return tr("Moving to Trash %lld/%lld", done, total)
    }
    static func confirmPermanentDialog(_ count: Int) -> String {
        tr("Permanently delete %lld files? This cannot be undone!", count)
    }
    static func confirmTrashDialog(_ count: Int) -> String {
        tr("Move %lld files to Trash?", count)
    }
    static var permanentDialogMessage: String {
        tr("Files will be removed from the card immediately. They cannot be restored from Trash or with Undo (⌘Z).")
    }
    static var trashDialogMessage: String {
        tr("Files will be moved to Trash. You can restore them from Trash or with Undo (⌘Z).")
    }

    // MARK: - Editor

    static var sectionRotateCrop: String { tr("Rotate / Crop") }
    static var sectionLight: String { tr("Light") }
    static var sectionColor: String { tr("Color") }
    static var sectionDetail: String { tr("Detail") }
    static var sectionCurve: String { tr("Curve") }
    static var rotateLeftHelp: String { tr("Rotate left 90°") }
    static var rotateRightHelp: String { tr("Rotate right 90°") }
    static var flipHorizontalHelp: String { tr("Flip horizontal") }
    static var crop: String { tr("Crop") }
    static var straighten: String { tr("Straighten") }
    static var autoLevel: String { tr("Auto level") }
    static var analyzing: String { tr("Analyzing…") }
    static var resetGeometry: String { tr("Reset geometry") }
    static var exposureAdj: String { tr("Exposure") }
    static var brightness: String { tr("Brightness") }
    static var contrast: String { tr("Contrast") }
    static var highlights: String { tr("Highlights") }
    static var shadows: String { tr("Shadows") }
    static var hdr: String { tr("HDR") }
    static var saturation: String { tr("Saturation") }
    static var vibrance: String { tr("Vibrance") }
    static var temperature: String { tr("Temperature") }
    static var tint: String { tr("Tint") }
    static var sharpen: String { tr("Sharpen") }
    static var vignette: String { tr("Vignette") }
    static var curveHint: String {
        tr("Drag on the curve to adjust · Right-click a point to remove")
    }
    static var resetCurve: String { tr("Reset curve") }
    static var originalOverlay: String { tr("Original") }
    static var resetAll: String { tr("Reset all") }
    static var compare: String { tr("Compare") }
    static var compareHelp: String { tr("Hold to compare with original") }
    static var export: String { tr("Export") }
    static var cropFree: String { tr("Free") }
    static var cropOriginal: String { tr("Original ratio") }

    // MARK: - Export

    static var exportTitle: String { tr("Export edited photo") }
    static var exportHint: String {
        tr("The original file is not modified. Edits are saved as a new file.")
    }
    static var quality: String { tr("Quality") }
    static var qualityHint: String { tr("Lower values mean smaller files and more quality loss.") }
    static var resize: String { tr("Resize") }
    static var exporting: String { tr("Exporting…") }
    static var saveAs: String { tr("Save as…") }
    static var exportToFolder: String { tr("Export to source folder") }
    static var originalSize: String { tr("Original size") }
    static func longEdgePx(_ value: Int) -> String { tr("Long edge %lld px", value) }

    // MARK: - Settings

    static var prefetchNeighbors: String { tr("Prefetch adjacent photos") }
    static var prefetchOff: String { tr("Off") }
    static func prefetchPerSide(_ n: Int) -> String { tr("%lld per side", n) }
    static var prefetchSection: String { tr("Preview / cache") }
    static var prefetchFooter: String {
        tr("After opening a preview, nearby photos are decoded in the background (RAW is slow; prefetch makes flipping instant). Higher counts use more memory.")
    }
    static var prefetchHintOff: String {
        tr("Prefetch is off — each photo is decoded on demand (lowest memory use).")
    }
    static func prefetchHintOn(_ total: Int, _ mb: Int) -> String {
        tr("About %lld photos prefetched (~%lld MB, auto-evicted when full).", total, mb)
    }

    // MARK: - About

    static func version(_ v: String) -> String { tr("Version %@", v) }
    static var aboutTagline: String {
        tr("Lightweight storage-card media manager · RAW/JPG paired deletion · Simple editing")
    }
    static var sponsorTitle: String { tr("Support the project ❤️") }
    static var sponsorBlurb: String {
        tr("If Siftly helps your workflow, consider buying the author a coffee.")
    }
    static var wechat: String { tr("WeChat") }
    static var alipay: String { tr("Alipay") }
    static var wechatQRHint: String { tr("Scan with WeChat to sponsor") }
    static var alipayQRHint: String { tr("Scan with Alipay to sponsor") }
    static var qrNotFound: String { tr("QR code not found") }
    static var paypalOnline: String { tr("Sponsor via PayPal") }
    static var openPayPal: String { tr("Open PayPal page") }
    static var copyLink: String { tr("Copy link") }

    // MARK: - Curve editor

    static var deleteCurvePoint: String { tr("Delete point") }

    // MARK: - Status messages

    enum Status {
        static var noCards: String { tr("No storage cards detected") }
        static var cardRemoved: String { tr("Storage card removed") }
        static func scanning(_ scope: String) -> String { tr("Scanning %@…", scope) }
        static func scanningFound(_ count: Int) -> String { tr("Scanning… found %lld files", count) }
        static func multiCardSummary(_ cards: Int, _ files: Int, _ paired: Int) -> String {
            tr("%lld cards · %lld files · %lld paired", cards, files, paired)
        }
        static func fileCount(_ count: Int) -> String { tr("%lld files", count) }
        static var scanFailed: String { tr("Scan failed") }
        static func pairingRule(_ name: String, _ paired: Int) -> String {
            tr("Pairing: %@ · %lld paired", name, paired)
        }
        static func exported(_ name: String) -> String { tr("Exported: %@", name) }
        static func permanentlyDeleted(_ count: Int) -> String {
            tr("Permanently deleted %lld files", count)
        }
        static func movedToTrash(_ count: Int) -> String { tr("Moved %lld files to Trash", count) }
        static func restored(_ count: Int) -> String { tr("Restored %lld files", count) }
    }

    // MARK: - Errors

    enum Error {
        static var scanContext: String { tr("Scan storage card") }
        static func accessDenied(_ context: String) -> String {
            tr("%@ failed: cannot access the folder. Grant Siftly Full Disk Access in System Settings > Privacy & Security.", context)
        }
        static func permissionDenied(_ context: String) -> String {
            tr("%@ failed: permission denied. Grant Siftly file access in System Settings.", context)
        }
        static func generic(_ context: String, _ message: String) -> String {
            tr("%@ failed: %@", context, message)
        }
        static func exportFailed(_ message: String) -> String { tr("Export failed: %@", message) }
        static var cardRemovedCancelDelete: String {
            tr("Storage card was removed; deletion cancelled.")
        }
        static func partialDelete(_ count: Int, _ verb: String, _ names: String, _ suffix: String) -> String {
            tr("%lld files could not be %@ (may be in use): %@%@", count, verb, names, suffix)
        }
        static func andMoreCount(_ count: Int) -> String { tr(" and %lld more", count) }
        static var verbDelete: String { tr("deleted") }
        static var verbTrash: String { tr("moved to Trash") }
        static func restoreFailed(_ count: Int) -> String {
            tr("%lld files could not be restored (they may have been emptied from Trash).", count)
        }
        static func cannotAccessDirectory(_ path: String) -> String {
            tr("Cannot access folder: %@", path)
        }
        static var trashNotSupported: String { tr("Move to Trash is not supported on this platform") }
    }
}
