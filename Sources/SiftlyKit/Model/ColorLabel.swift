import Foundation

/// Finder-style color label.
public enum ColorLabel: String, Codable, CaseIterable, Identifiable {
    case none, red, orange, yellow, green, blue, purple, gray

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return L10n.labelNone
        case .red: return L10n.labelRed
        case .orange: return L10n.labelOrange
        case .yellow: return L10n.labelYellow
        case .green: return L10n.labelGreen
        case .blue: return L10n.labelBlue
        case .purple: return L10n.labelPurple
        case .gray: return L10n.labelGray
        }
    }
}
