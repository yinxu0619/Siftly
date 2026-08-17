import Foundation

/// A user-applied mark on a file (rating + color label).
public struct FileMark: Codable, Equatable {
    public var rating: Rating
    public var label: ColorLabel

    public init(rating: Rating = .none, label: ColorLabel = .none) {
        self.rating = rating
        self.label = label
    }

    public var isEmpty: Bool { rating == .none && label == .none }
}

/// Persists ratings/labels as a lightweight sidecar index in Application Support.
/// The card's original files are never copied or modified. Keys are
/// `volumeID::relativePath` so marks follow a card across remounts.
public final class LibraryStore {
    private var marks: [String: FileMark] = [:]
    private let fileURL: URL

    public init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = support.appendingPathComponent("Siftly", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("marks.json")
        load()
    }

    public static func key(volumeID: String, fileURL: URL, volumeURL: URL) -> String {
        // Strip the volume mount point as a *prefix* only. (Using
        // `replacingOccurrences` here would also rewrite matches deeper in the
        // path, producing a key that collides with unrelated files.)
        let path = fileURL.path
        let prefix = volumeURL.path
        let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        return "\(volumeID)::\(relative)"
    }

    public func mark(forKey key: String) -> FileMark {
        marks[key] ?? FileMark()
    }

    public func setMark(_ mark: FileMark, forKey key: String) {
        apply(mark, forKey: key)
        save()
    }

    /// Batch variant: applies many marks with a single encode + disk write.
    /// Used by the "rate/label the whole selection" commands, which would
    /// otherwise rewrite the entire index once per file.
    public func setMarks(_ updates: [String: FileMark]) {
        guard !updates.isEmpty else { return }
        for (key, mark) in updates { apply(mark, forKey: key) }
        save()
    }

    /// Drops marks for files that no longer exist (e.g. after a deletion), so
    /// the index doesn't grow without bound and stale ratings can't reattach to
    /// a later file that happens to reuse the same name.
    public func removeMarks(forKeys keys: [String]) {
        var changed = false
        for key in keys where marks.removeValue(forKey: key) != nil { changed = true }
        if changed { save() }
    }

    private func apply(_ mark: FileMark, forKey key: String) {
        if mark.isEmpty {
            marks.removeValue(forKey: key)
        } else {
            marks[key] = mark
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: FileMark].self, from: data)
        else { return }
        marks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(marks) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
