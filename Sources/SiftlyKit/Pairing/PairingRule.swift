import Foundation

/// Describes which file extensions pair together. Two files pair when they live
/// in the same directory, share the same base name, and their extensions belong
/// to the *same* group.
public struct PairingRule: Codable, Equatable {
    public var name: String
    /// Each inner array is a set of extensions (lowercased, no dot) that pair.
    public var groups: [[String]]
    public var caseInsensitiveName: Bool
    /// When true, files pair by base name regardless of directory/volume. Used
    /// for cross-card (dual-slot RAW/JPG on separate cards) linked deletion.
    public var crossLocation: Bool

    public init(
        name: String,
        groups: [[String]],
        caseInsensitiveName: Bool = true,
        crossLocation: Bool = false
    ) {
        self.name = name
        self.groups = groups.map { $0.map { $0.lowercased() } }
        self.caseInsensitiveName = caseInsensitiveName
        self.crossLocation = crossLocation
    }

    /// Non-RAW partners that a RAW file pairs with.
    private static let companions = ["jpg", "jpeg", "heic", "heif"]

    /// Universal rule: any supported RAW pairs with JPG/HEIC. Works across Sony,
    /// Canon, Nikon, Fuji, etc. out of the box. This is the default.
    public static let universal = PairingRule(
        name: "通用 RAW + JPG",
        groups: [Array(MediaCatalog.rawExtensions) + companions]
    )

    public static let sony = PairingRule(name: "索尼 ARW + JPG", groups: [["arw"] + companions])
    public static let canon = PairingRule(name: "佳能 CR2/CR3 + JPG", groups: [["cr2", "cr3"] + companions])
    public static let nikon = PairingRule(name: "尼康 NEF/NRW + JPG", groups: [["nef", "nrw"] + companions])
    public static let fuji = PairingRule(name: "富士 RAF + JPG", groups: [["raf"] + companions])

    /// Selectable presets shown in the UI.
    public static let presets: [PairingRule] = [universal, sony, canon, nikon, fuji]

    public static let `default` = universal

    /// All extensions referenced by the rule.
    public var allExtensions: Set<String> {
        Set(groups.flatMap { $0 })
    }
}
