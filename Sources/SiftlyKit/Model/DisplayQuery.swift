import Foundation

struct DisplayQuery: Sendable {
    let files: [MediaFile]
    let searchText: String
    let formatFilter: FormatFilter
    let minRating: Int
    let labelFilter: ColorLabel?
    let sortKey: SortKey
    let sortAscending: Bool
    let pairing: PairingResult
    let marks: [String: FileMark]

    private func mark(_ file: MediaFile) -> FileMark {
        guard let id = file.volumeID, let root = file.volumeURL else { return FileMark() }
        return marks[LibraryStore.key(volumeID: id, fileURL: file.url, volumeURL: root)] ?? FileMark()
    }

    func evaluate() -> (files: [MediaFile], index: [URL: Int]) {
        var result = files

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.name.lowercased().contains(query) }
        }

        switch formatFilter {
        case .all: break
        case .raw: result = result.filter { $0.isRAW }
        case .jpg: result = result.filter { MediaCatalog.jpegExtensions.contains($0.ext) }
        case .video: result = result.filter { $0.isVideo }
        case .paired: result = result.filter { pairing.isPaired($0.url) }
        case .unpaired: result = result.filter { !pairing.isPaired($0.url) }
        }

        if minRating > 0 {
            result = result.filter { mark($0).rating.stars >= minRating }
        }
        if let label = labelFilter {
            result = result.filter { mark($0).label == label }
        }

        switch sortKey {
        case .date:
            let ascending = sortAscending
            result.sort {
                let l = $0.modificationDate ?? .distantPast
                let r = $1.modificationDate ?? .distantPast
                return ascending ? l < r : l > r
            }
        case .name:
            let ascending = sortAscending
            result.sort {
                let order = $0.name.localizedStandardCompare($1.name)
                return ascending ? order == .orderedAscending : order == .orderedDescending
            }
        case .size:
            let ascending = sortAscending
            result.sort {
                let l = $0.fileSize ?? 0
                let r = $1.fileSize ?? 0
                return ascending ? l < r : l > r
            }
        }

        var index: [URL: Int] = [:]
        index.reserveCapacity(result.count)
        for (position, file) in result.enumerated() { index[file.url] = position }
        return (result, index)
    }
}
