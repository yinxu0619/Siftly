#if os(macOS)
import Foundation

/// macOS file enumeration. Uses a directory enumerator with prefetched resource
/// keys so file size / modification date are read in one pass.
public final class MacFileSystemService: FileSystemService {
    private let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .fileSizeKey,
        .contentModificationDateKey
    ]

    public init() {}

    public func scanMediaFiles(
        in directory: URL,
        extensions: Set<String>,
        batchSize: Int,
        onBatch: ([MediaFile]) -> Bool
    ) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FileScanError.cannotAccess(directory)
        }

        let effectiveBatch = max(1, batchSize)
        let keys = Set(resourceKeys)
        var batch: [MediaFile] = []
        if effectiveBatch != Int.max { batch.reserveCapacity(effectiveBatch) }

        for case let url as URL in enumerator {
            // Filter on the extension *before* touching the file system. Cards
            // carry a lot of sidecar noise (.THM/.XML/.CTG); reading resource
            // values for those is pure overhead.
            let ext = url.pathExtension.lowercased()
            if !extensions.isEmpty && !extensions.contains(ext) { continue }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            batch.append(
                MediaFile(
                    url: url,
                    fileSize: values?.fileSize.map(Int64.init),
                    modificationDate: values?.contentModificationDate
                )
            )
            if batch.count >= effectiveBatch {
                if !onBatch(batch) { return }
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty {
            _ = onBatch(batch)
        }
    }
}
#endif
