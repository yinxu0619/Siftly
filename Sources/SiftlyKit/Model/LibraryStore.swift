import Foundation

/// A user-applied mark on a file (rating + color label).
public struct FileMark: Codable, Equatable, Sendable {
    public var rating: Rating
    public var label: ColorLabel
    /// Non-destructive editor state, so reopening a photo restores the edit.
    /// Optional and decoded with `decodeIfPresent`, so indexes written before
    /// this existed still load.
    public var adjustments: ImageAdjustments?

    public init(
        rating: Rating = .none,
        label: ColorLabel = .none,
        adjustments: ImageAdjustments? = nil
    ) {
        self.rating = rating
        self.label = label
        self.adjustments = adjustments
    }

    public var isEmpty: Bool { rating == .none && label == .none && !hasEdits }

    /// True when the editor holds a non-identity adjustment for this file.
    public var hasEdits: Bool {
        guard let adjustments else { return false }
        return !adjustments.isIdentity
    }
}

/// Persists ratings/labels as a lightweight sidecar index in Application Support.
/// The card's original files are never copied or modified. Keys are
/// `volumeID::relativePath` so marks follow a card across remounts.
public final class LibraryStore {
    private var marks: [String: FileMark] = [:]
    private let fileURL: URL
    private let persistence: MarkPersistence
    public var onSaveError: ((Error) -> Void)?

    public init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? support.appendingPathComponent("Siftly/marks.json")
        self.persistence = MarkPersistence(fileURL: self.fileURL)
        load()
    }

    deinit { try? persistence.flush() }

    /// Drain the latest snapshot before normal app termination or an explicit save.
    public func flush() throws { try persistence.flush() }

    public static func key(volumeID: String, fileURL: URL, volumeURL: URL) -> String {
        // Strip the volume mount point as a *prefix* only. (Using
        // `replacingOccurrences` here would also rewrite matches deeper in the
        // path, producing a key that collides with unrelated files.)
        let path = fileURL.path
        let prefix = volumeURL.path
        let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        return "\(volumeID)::\(relative)"
    }

    var snapshot: [String: FileMark] { marks }

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
        persistence.enqueue(marks, onError: onSaveError)
    }
}

/// The UI owns the in-memory marks; encoding and atomic disk writes happen on
/// one queue. A burst of edits replaces the pending snapshot, not the disk file.
private final class MarkPersistence: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.siftly.marks", qos: .utility)
    private let lock = NSLock()
    private var pending: ([String: FileMark], ((Error) -> Void)?)?
    private var scheduled = false
    private var lastError: Error?

    init(fileURL: URL) { self.fileURL = fileURL }

    func enqueue(_ marks: [String: FileMark], onError: ((Error) -> Void)?) {
        lock.lock()
        pending = (marks, onError)
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needsSchedule {
            queue.asyncAfter(deadline: .now() + 0.25) { self.drain() }
        }
    }

    private func drain() {
        lock.lock()
        let snapshot = pending
        pending = nil
        scheduled = false
        lock.unlock()
        guard let (marks, onError) = snapshot else { return }
        do {
            let data = try JSONEncoder().encode(marks)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error
            onError?(error)
        }
    }

    func flush() throws {
        try queue.sync {
            drain()
            if let lastError { throw lastError }
        }
    }
}
