import Foundation

/// A mounted storage volume (SD / CFexpress card, USB reader, etc.).
public struct Volume: Identifiable, Hashable {
    /// Stable identifier: volume UUID when available, otherwise the mount path.
    public let id: String
    public let name: String
    public let url: URL
    public let isRemovable: Bool
    public var totalCapacity: Int64?
    public var availableCapacity: Int64?

    public init(
        id: String,
        name: String,
        url: URL,
        isRemovable: Bool,
        totalCapacity: Int64? = nil,
        availableCapacity: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isRemovable = isRemovable
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }

    public var capacityDescription: String {
        guard let total = totalCapacity else { return "" }
        let used = total - (availableCapacity ?? total)
        let f = ByteCountFormatter()
        f.countStyle = .file
        return "\(f.string(fromByteCount: used)) / \(f.string(fromByteCount: total))"
    }
}
