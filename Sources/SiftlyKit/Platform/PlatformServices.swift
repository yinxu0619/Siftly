import Foundation
import CoreGraphics

// MARK: - Cross-platform service protocols
//
// These protocols are the seam between platform-agnostic logic/UI and the
// concrete OS integration. macOS implementations live in `Platform/macOS`.
// Windows implementations are stubbed in `Platform/Windows` and guarded by
// `#if os(Windows)` so the interface is reserved without affecting the macOS
// build.

/// Discovers mounted removable volumes and reports hot-plug changes.
public protocol VolumeService: AnyObject {
    func currentRemovableVolumes() -> [Volume]
    func startObserving(onChange: @escaping () -> Void)
    func stopObserving()
}

/// Enumerates media files on disk.
public protocol FileSystemService: AnyObject {
    /// Convenience: returns all matching files at once (used by tests).
    func enumerateMediaFiles(in directory: URL, extensions: Set<String>) throws -> [MediaFile]

    /// Streaming enumeration. `onBatch` is invoked repeatedly with chunks of up
    /// to `batchSize` files so the UI can render incrementally and memory stays
    /// bounded on very large cards. Runs on the calling (background) thread.
    func scanMediaFiles(
        in directory: URL,
        extensions: Set<String>,
        batchSize: Int,
        onBatch: ([MediaFile]) -> Void
    ) throws
}

public extension FileSystemService {
    func enumerateMediaFiles(in directory: URL, extensions: Set<String>) throws -> [MediaFile] {
        var all: [MediaFile] = []
        try scanMediaFiles(in: directory, extensions: extensions, batchSize: Int.max) { batch in
            all.append(contentsOf: batch)
        }
        return all
    }
}

/// Moves files to the OS recycle bin / Trash (never permanent deletion).
public protocol TrashService: AnyObject {
    /// Returns the resulting location inside the Trash (used for undo) when known.
    func moveToTrash(_ url: URL) throws -> URL?

    /// Restores a previously-trashed item back to its original location (undo).
    func restoreItem(at trashURL: URL, to originalURL: URL) throws
}

/// Generates thumbnail images for media files.
public protocol ThumbnailService: AnyObject {
    func thumbnail(for url: URL, size: CGSize) async -> CGImage?
}

// MARK: - Errors

public enum FileScanError: LocalizedError {
    case cannotAccess(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotAccess(let url):
            return "无法访问目录：\(url.path)"
        }
    }
}

public enum TrashError: LocalizedError {
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "当前平台暂不支持移入废纸篓"
        }
    }
}
