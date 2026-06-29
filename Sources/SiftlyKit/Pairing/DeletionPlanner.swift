import Foundation

/// A computed, confirmable plan describing exactly what will be moved to Trash,
/// distinguishing user-selected files from automatically-added paired files.
public struct DeletionPlan {
    public let directlySelected: [MediaFile]
    public let pairedAdditions: [MediaFile]

    public init(directlySelected: [MediaFile], pairedAdditions: [MediaFile]) {
        self.directlySelected = directlySelected
        self.pairedAdditions = pairedAdditions
    }

    public var allFiles: [MediaFile] { directlySelected + pairedAdditions }
    public var urls: [URL] { allFiles.map { $0.url } }
    public var count: Int { directlySelected.count + pairedAdditions.count }
    public var totalSize: Int64 { allFiles.compactMap { $0.fileSize }.reduce(0, +) }
    public var isEmpty: Bool { count == 0 }

    public var totalSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

/// Expands a user selection to include all paired files, deduplicated.
public enum DeletionPlanner {
    public static func plan(
        for selected: Set<URL>,
        pairing: PairingResult,
        allFiles: [MediaFile]
    ) -> DeletionPlan {
        var byURL: [URL: MediaFile] = [:]
        for file in allFiles { byURL[file.url] = file }

        var fullSet = Set<URL>()
        for url in selected {
            fullSet.insert(url)
            fullSet.formUnion(pairing.partners(of: url))
        }

        let additions = fullSet.subtracting(selected)

        let directFiles = selected
            .compactMap { byURL[$0] }
            .sorted { $0.name < $1.name }
        let addedFiles = additions
            .compactMap { byURL[$0] }
            .sorted { $0.name < $1.name }

        return DeletionPlan(directlySelected: directFiles, pairedAdditions: addedFiles)
    }
}
