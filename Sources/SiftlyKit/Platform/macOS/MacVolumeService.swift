#if os(macOS)
import Foundation
import AppKit

/// macOS volume discovery via `FileManager.mountedVolumeURLs` plus hot-plug
/// notifications from `NSWorkspace`.
public final class MacVolumeService: VolumeService {
    private var observers: [NSObjectProtocol] = []

    private let resourceKeys: [URLResourceKey] = [
        .volumeNameKey,
        .volumeIsRemovableKey,
        .volumeIsInternalKey,
        .volumeIsBrowsableKey,
        .volumeUUIDStringKey,
        .volumeCreationDateKey,
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey
    ]

    public init() {}

    deinit { stopObserving() }

    public func currentRemovableVolumes() -> [Volume] {
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: resourceKeys,
            options: [.skipHiddenVolumes]
        ) else { return [] }

        var volumes: [Volume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)) else { continue }
            if values.volumeIsBrowsable == false { continue }

            let isRemovable = values.volumeIsRemovable ?? false
            let isInternal = values.volumeIsInternal ?? true
            // A card reader is removable; some readers report non-internal. We
            // treat "removable OR not internal" as an external card, but never
            // the boot volume ("/").
            guard isRemovable || !isInternal else { continue }
            if url.path == "/" { continue }

            let name = values.volumeName ?? url.lastPathComponent
            let id = Self.identity(
                uuid: values.volumeUUIDString,
                volumeCreationDate: values.volumeCreationDate,
                contentCreationDate: Self.contentCreationDate(at: url),
                mountPath: url.path
            )
            volumes.append(
                Volume(
                    id: id,
                    name: name,
                    url: url,
                    isRemovable: isRemovable,
                    totalCapacity: values.volumeTotalCapacity.map(Int64.init),
                    availableCapacity: values.volumeAvailableCapacity.map(Int64.init)
                )
            )
        }
        return volumes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Stable per-card identity, used as the namespace for persisted ratings and
    /// labels. Camera cards are usually exFAT/FAT32 and report no volume UUID,
    /// and they are almost always named "NO NAME" / "Untitled" — so falling back
    /// to the mount path alone would make every such card share one namespace
    /// and inherit the previous card's marks.
    ///
    /// The name is deliberately *not* part of the identity, so renaming a card
    /// keeps its marks.
    ///
    /// Three chances before the colliding mount-path fallback, because whether
    /// macOS synthesizes a volume creation date for exFAT is unverified (it
    /// needs a real card to confirm):
    ///   1. volume UUID — present on APFS/HFS+, absent on most camera cards
    ///   2. volume creation date — set at format time
    ///   3. content creation date — the DCIM directory, which on a camera card
    ///      is a real exFAT directory entry with a real timestamp, or failing
    ///      that the volume's root directory
    static func identity(
        uuid: String?,
        volumeCreationDate: Date?,
        contentCreationDate: Date?,
        mountPath: String
    ) -> String {
        if let uuid, !uuid.isEmpty { return uuid }
        if let created = volumeCreationDate {
            return "created-\(Int(created.timeIntervalSince1970))"
        }
        if let created = contentCreationDate {
            return "content-\(Int(created.timeIntervalSince1970))"
        }
        return mountPath
    }

    /// Timestamp of the card's contents: the camera's DCIM folder when present,
    /// otherwise the volume root.
    private static func contentCreationDate(at volume: URL) -> Date? {
        let dcim = volume.appendingPathComponent("DCIM", isDirectory: true)
        if let date = (try? dcim.resourceValues(forKeys: [.creationDateKey]))?.creationDate {
            return date
        }
        return (try? volume.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    public func startObserving(onChange: @escaping () -> Void) {
        stopObserving()
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                onChange()
            }
        }
    }

    public func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }
}
#endif
