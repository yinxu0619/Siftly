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
        let relative = fileURL.path.replacingOccurrences(of: volumeURL.path, with: "")
        return "\(volumeID)::\(relative)"
    }

    public func mark(forKey key: String) -> FileMark {
        marks[key] ?? FileMark()
    }

    public func setMark(_ mark: FileMark, forKey key: String) {
        if mark.isEmpty {
            marks.removeValue(forKey: key)
        } else {
            marks[key] = mark
        }
        save()
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
