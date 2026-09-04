import Foundation

/// A single media file discovered on a card. This is a lightweight value type:
/// it never holds image data, only the URL and cheap metadata, to keep memory
/// usage low for very large cards.
public struct MediaFile: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    /// File name without extension. Used as the pairing key.
    public let baseName: String
    /// Lowercased file extension (no dot).
    public let ext: String
    public let directory: URL
    public var fileSize: Int64?
    public var modificationDate: Date?

    // Owning volume, stamped during scanning. Enables cross-card pairing and
    // correct, volume-relative mark keys when browsing multiple cards at once.
    public var volumeID: String?
    public var volumeName: String?
    public var volumeURL: URL?

    public init(url: URL, fileSize: Int64? = nil, modificationDate: Date? = nil) {
        self.url = url
        self.name = url.lastPathComponent
        self.baseName = url.deletingPathExtension().lastPathComponent
        self.ext = url.pathExtension.lowercased()
        self.directory = url.deletingLastPathComponent()
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    public var isRAW: Bool { MediaCatalog.rawExtensions.contains(ext) }
    public var isVideo: Bool { MediaCatalog.videoExtensions.contains(ext) }
}

/// Known media extensions. Scanning includes these so JPG/HEIC etc. are shown
/// even when they are not part of the active pairing rule.
public enum MediaCatalog {
    public static let rawExtensions: Set<String> = [
        "arw", "cr2", "cr3", "nef", "nrw", "raf", "rw2", "orf",
        "dng", "pef", "srw", "x3f", "raw", "3fr", "erf", "mef"
    ]

    public static let jpegExtensions: Set<String> = ["jpg", "jpeg"]

    public static let otherImageExtensions: Set<String> = [
        "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp"
    ]

    /// Clips written by stills cameras, drones and action cams. Cards almost
    /// always hold these alongside photos; leaving them out made Siftly's space
    /// accounting disagree with the Finder and let a paired video survive the
    /// deletion of the photo it belongs to.
    public static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mts", "m2ts", "mxf", "3gp", "mpg", "mpeg", "wmv"
    ]

    public static let imageExtensions: Set<String> =
        rawExtensions.union(jpegExtensions).union(otherImageExtensions)

    /// Everything the grid can show.
    public static let allMediaExtensions: Set<String> =
        imageExtensions.union(videoExtensions)
}
