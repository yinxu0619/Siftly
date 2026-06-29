#if os(macOS)
import Foundation

/// Moves files to the macOS Trash. Never deletes permanently.
public final class MacTrashService: TrashService {
    public init() {}

    @discardableResult
    public func moveToTrash(_ url: URL) throws -> URL? {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    public func restoreItem(at trashURL: URL, to originalURL: URL) throws {
        let fm = FileManager.default
        let parent = originalURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try fm.moveItem(at: trashURL, to: originalURL)
    }
}
#endif
