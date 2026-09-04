import Foundation

/// One file to copy, and where it lands.
public struct ImportItem: Equatable, Sendable {
    public let source: MediaFile
    public let destination: URL

    public init(source: MediaFile, destination: URL) {
        self.source = source
        self.destination = destination
    }
}

/// Why a file was left out of the copy list.
public enum ImportSkipReason: Equatable, Sendable {
    /// A file of the same name and size is already at the destination.
    case alreadyImported
}

public struct ImportSkip: Equatable, Sendable {
    public let source: MediaFile
    public let reason: ImportSkipReason
}

public struct ImportPlan: Equatable, Sendable {
    public let items: [ImportItem]
    public let skipped: [ImportSkip]

    public init(items: [ImportItem] = [], skipped: [ImportSkip] = []) {
        self.items = items
        self.skipped = skipped
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
    public var totalBytes: Int64 { items.compactMap { $0.source.fileSize }.reduce(0, +) }
    public var totalSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

/// Works out the destination path for every file, resolving collisions.
///
/// Pure logic: the filesystem is reached only through the injected `existingSize`
/// probe, so the interesting cases (re-import, name clashes between two cards)
/// are testable without touching disk.
public enum ImportPlanner {

    /// - Parameter existingSize: byte size of a file already at that path, or
    ///   `nil` when nothing is there.
    public static func plan(
        for files: [MediaFile],
        settings: ImportSettings,
        existingSize: (URL) -> Int64?
    ) -> ImportPlan {
        guard let root = settings.destination else { return ImportPlan() }

        var items: [ImportItem] = []
        var skipped: [ImportSkip] = []
        // Destinations claimed earlier in this same run. Two cards in cross-card
        // mode routinely hold different photos under the same name, so the
        // filesystem probe alone is not enough to keep them apart.
        var claimed = Set<String>()

        for file in files {
            let folder = subfolder(for: file, organization: settings.organization)
                .reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }

            let base = file.url.deletingPathExtension().lastPathComponent
            let ext = file.url.pathExtension

            var candidate = folder.appendingPathComponent(
                ext.isEmpty ? base : "\(base).\(ext)"
            )
            var suffix = 1
            var alreadyImported = false

            while claimed.contains(candidate.path) || existingSize(candidate) != nil {
                // Same name *and* same size at the destination: this is a
                // re-import of a file already brought over, not a clash.
                if !claimed.contains(candidate.path),
                   let size = existingSize(candidate),
                   let sourceSize = file.fileSize,
                   size == sourceSize {
                    alreadyImported = true
                    break
                }
                let name = ext.isEmpty ? "\(base)-\(suffix)" : "\(base)-\(suffix).\(ext)"
                candidate = folder.appendingPathComponent(name)
                suffix += 1
            }

            if alreadyImported {
                skipped.append(ImportSkip(source: file, reason: .alreadyImported))
            } else {
                claimed.insert(candidate.path)
                items.append(ImportItem(source: file, destination: candidate))
            }
        }

        return ImportPlan(items: items, skipped: skipped)
    }

    /// Path components below the destination root for a given file.
    static func subfolder(for file: MediaFile, organization: ImportOrganization) -> [String] {
        switch organization {
        case .flat:
            return []
        case .byDate:
            return [day(file)]
        case .byYearMonth:
            return [year(file), month(file)]
        case .byDateAndKind:
            return [day(file), MediaKind(file).rawValue]
        }
    }

    // Capture time is approximated by the file's modification date, which cameras
    // set when writing the frame. Reading EXIF for every file would mean opening
    // each one during planning — far too slow for a full card.
    private static func date(_ file: MediaFile) -> Date { file.modificationDate ?? Date() }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // stable folder names
        f.dateFormat = format
        return f
    }

    private static func day(_ file: MediaFile) -> String {
        formatter("yyyy-MM-dd").string(from: date(file))
    }
    private static func year(_ file: MediaFile) -> String {
        formatter("yyyy").string(from: date(file))
    }
    private static func month(_ file: MediaFile) -> String {
        formatter("yyyy-MM").string(from: date(file))
    }
}
