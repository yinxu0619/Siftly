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
    /// and inherit the previous card's marks. The volume creation date (set at
    /// format time) disambiguates them.
    ///
    /// The name is deliberately *not* part of the identity, so renaming a card
    /// keeps its marks. A second-resolution format timestamp is specific enough
    /// on its own.
    ///
    /// NOTE: exFAT has no standard "volume created" field in its boot sector, so
    /// whether macOS synthesizes one for a camera card is unverified — it needs
    /// a real card to confirm. If it comes back nil we fall through to the mount
    /// path (the old, colliding behaviour) and the fallback has to become the
    /// exFAT volume serial number, read via DiskArbitration or the boot sector.
    static func identity(uuid: String?, volumeCreationDate: Date?, mountPath: String) -> String {
        if let uuid, !uuid.isEmpty { return uuid }
        if let created = volumeCreationDate {
            return "created-\(Int(created.timeIntervalSince1970))"
        }
        return mountPath
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
