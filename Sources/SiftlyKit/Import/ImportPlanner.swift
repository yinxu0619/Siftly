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
    /// A file with verified identical content is already at the destination.
    case alreadyImported
}

public struct ImportSkip: Equatable, Sendable {
    public let source: MediaFile
    public let reason: ImportSkipReason
}

public struct ImportPlan: Equatable, Sendable {
    public let items: [ImportItem]
    public let skipped: [ImportSkip]
    /// The inputs that determine paths, retained to reject a stale confirmation.
    public let settings: ImportSettings?

    public init(items: [ImportItem] = [], skipped: [ImportSkip] = [], settings: ImportSettings? = nil) {
        self.items = items
        self.skipped = skipped
        self.settings = settings
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
/// Size and content probes are injectable so collision handling can be tested
/// without disk access. The default content probe compares SHA-256 checksums.
public enum ImportPlanner {

    /// - Parameter existingSize: byte size of a file already at that path, or
    ///   `nil` when nothing is there.
    public static func plan(
        for files: [MediaFile],
        settings: ImportSettings,
        contentsEqual: (URL, URL) -> Bool = { source, destination in
            guard let a = try? FileCopier.checksum(of: source),
                  let b = try? FileCopier.checksum(of: destination) else { return false }
            return a == b
        },
        existingSize: (URL) -> Int64?
    ) -> ImportPlan {
        guard let root = settings.destination else { return ImportPlan() }

        let dates = DateFolders()
        var items: [ImportItem] = []
        var skipped: [ImportSkip] = []
        // Destinations claimed earlier in this same run. Two cards in cross-card
        // mode routinely hold different photos under the same name, so the
        // filesystem probe alone is not enough to keep them apart.
        var claimed = Set<String>()

        for file in files {
            if Task.isCancelled { return ImportPlan() }
            let folder = subfolder(for: file, organization: settings.organization, dates: dates)
                .reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }

            let base = file.url.deletingPathExtension().lastPathComponent
            let ext = file.url.pathExtension

            var candidate = folder.appendingPathComponent(
                ext.isEmpty ? base : "\(base).\(ext)"
            )
            var suffix = 1
            var alreadyImported = false

            while claimed.contains(candidate.path) || existingSize(candidate) != nil {
                if Task.isCancelled { return ImportPlan() }
                // Size is only a cheap first pass. Camera filenames and byte
                // counts can repeat for entirely different photographs.
                if !claimed.contains(candidate.path),
                   let size = existingSize(candidate),
                   let sourceSize = file.fileSize,
                   size == sourceSize, contentsEqual(file.url, candidate) {
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

        return ImportPlan(items: items, skipped: skipped, settings: settings)
    }

    /// Path components below the destination root for a given file.
    static func subfolder(for file: MediaFile, organization: ImportOrganization) -> [String] {
        subfolder(for: file, organization: organization, dates: DateFolders())
    }

    private static func subfolder(for file: MediaFile, organization: ImportOrganization, dates: DateFolders) -> [String] {
        switch organization {
        case .flat:
            return []
        case .byDate:
            return [dates.day.string(from: file.modificationDate ?? dates.fallback)]
        case .byYearMonth:
            return [dates.year.string(from: file.modificationDate ?? dates.fallback), dates.month.string(from: file.modificationDate ?? dates.fallback)]
        case .byDateAndKind:
            return [dates.day.string(from: file.modificationDate ?? dates.fallback), MediaKind(file).rawValue]
        }
    }

    // Reused within one plan, never shared across concurrent planning tasks.
    private struct DateFolders {
        let fallback = Date()
        let day = formatter("yyyy-MM-dd")
        let year = formatter("yyyy")
        let month = formatter("yyyy-MM")
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
}
