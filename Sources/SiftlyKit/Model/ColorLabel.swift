import Foundation

/// Finder-style color label.
public enum ColorLabel: String, Codable, CaseIterable, Identifiable {
    case none, red, orange, yellow, green, blue, purple, gray

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .none: return "无"
        case .red: return "红"
        case .orange: return "橙"
        case .yellow: return "黄"
        case .green: return "绿"
        case .blue: return "蓝"
        case .purple: return "紫"
        case .gray: return "灰"
        }
    }
}
