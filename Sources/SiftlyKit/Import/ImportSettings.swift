import Foundation

/// How imported files are laid out inside the destination folder.
public enum ImportOrganization: String, CaseIterable, Identifiable, Sendable {
    /// Everything straight into the destination folder.
    case flat
    /// `2026-08-19/`
    case byDate
    /// `2026/2026-08/`
    case byYearMonth
    /// `2026-08-19/RAW`, `.../JPEG`, `.../Video`
    case byDateAndKind

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flat: return L10n.importOrgFlat
        case .byDate: return L10n.importOrgByDate
        case .byYearMonth: return L10n.importOrgByYearMonth
        case .byDateAndKind: return L10n.importOrgByDateAndKind
        }
    }

    /// A concrete example of the layout, shown under the picker.
    public var example: String {
        switch self {
        case .flat: return "DSC001.ARW"
        case .byDate: return "2026-08-19/DSC001.ARW"
        case .byYearMonth: return "2026/2026-08/DSC001.ARW"
        case .byDateAndKind: return "2026-08-19/RAW/DSC001.ARW"
        }
    }
}

/// The kind subfolder used by `.byDateAndKind`.
public enum MediaKind: String, Sendable {
    case raw = "RAW"
    case jpeg = "JPEG"
    case video = "Video"
    case other = "Other"

    public init(_ file: MediaFile) {
        if file.isRAW { self = .raw }
        else if file.isVideo { self = .video }
        else if MediaCatalog.jpegExtensions.contains(file.ext) { self = .jpeg }
        else { self = .other }
    }
}

/// User choices for an import run.
public struct ImportSettings: Equatable, Sendable {
    /// Destination root. `nil` until the user picks one.
    public var destination: URL?
    public var organization: ImportOrganization = .byDate
    /// Also bring each file's paired companions (RAW's JPG, a same-named clip),
    /// so importing never orphans half of a pair on the card.
    public var includesPairedFiles = true
    /// Verify the staged destination against the checksum computed during copying.
    public var verifies = true
    /// Move to Trash from the card after a *verified* copy.
    public var deletesAfterImport = false

    func hasSamePlanningInputs(as other: ImportSettings) -> Bool {
        destination == other.destination && organization == other.organization && includesPairedFiles == other.includesPairedFiles
    }

    public var requiresVerification: Bool { verifies || deletesAfterImport }

    public init() {}
}
