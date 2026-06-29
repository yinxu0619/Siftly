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
        onBatch: ([MediaFile]) -> Void
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
        var batch: [MediaFile] = []
        if effectiveBatch != Int.max { batch.reserveCapacity(effectiveBatch) }

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            if !extensions.isEmpty && !extensions.contains(ext) { continue }
            batch.append(
                MediaFile(
                    url: url,
                    fileSize: values?.fileSize.map(Int64.init),
                    modificationDate: values?.contentModificationDate
                )
            )
            if batch.count >= effectiveBatch {
                onBatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty {
            onBatch(batch)
        }
    }
}
#endif
