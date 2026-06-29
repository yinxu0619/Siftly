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
            let id = values.volumeUUIDString ?? url.path
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
