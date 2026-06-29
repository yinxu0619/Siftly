#if os(Windows)
import Foundation
import CoreGraphics

// MARK: - Windows porting seam
//
// These stubs reserve the platform interface for a future Windows port. They are
// intentionally excluded from the macOS build via `#if os(Windows)`.
//
// To bring up Windows:
//   1. VolumeService     -> enumerate drives via GetLogicalDrives / SetupAPI,
//                           watch WM_DEVICECHANGE for hot-plug.
//   2. FileSystemService -> recursive directory walk (already mostly portable
//                           via Foundation on Swift for Windows).
//   3. TrashService      -> SHFileOperation with FOF_ALLOWUNDO (Recycle Bin).
//   4. ThumbnailService  -> IShellItemImageFactory / WIC.

public final class WindowsVolumeService: VolumeService {
    public init() {}
    public func currentRemovableVolumes() -> [Volume] { [] }
    public func startObserving(onChange: @escaping () -> Void) {}
    public func stopObserving() {}
}

public final class WindowsFileSystemService: FileSystemService {
    public init() {}
    public func scanMediaFiles(
        in directory: URL,
        extensions: Set<String>,
        batchSize: Int,
        onBatch: ([MediaFile]) -> Void
    ) throws {
        // TODO(windows): port directory enumeration (Foundation FileManager is
        // mostly portable on Swift for Windows; emit batches via onBatch).
    }
}

public final class WindowsTrashService: TrashService {
    public init() {}
    public func moveToTrash(_ url: URL) throws -> URL? {
        // TODO(windows): SHFileOperation with FOF_ALLOWUNDO.
        throw TrashError.notImplemented
    }
    public func restoreItem(at trashURL: URL, to originalURL: URL) throws {
        // TODO(windows): restore from Recycle Bin via IFileOperation / shell APIs.
        throw TrashError.notImplemented
    }
}

public final class WindowsThumbnailService: ThumbnailService {
    public init() {}
    public func thumbnail(for url: URL, size: CGSize) async -> CGImage? {
        // TODO(windows): IShellItemImageFactory / WIC.
        return nil
    }
}
#endif
