import Foundation

/// Star rating, 0–5.
public enum Rating: Int, Codable, CaseIterable, Comparable {
    case none = 0, one, two, three, four, five

    public static func < (lhs: Rating, rhs: Rating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var stars: Int { rawValue }
}
