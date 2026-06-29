import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Output container format for an edited image.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg, heic, png, tiff

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .png: return "png"
        case .tiff: return "tif"
        }
    }

    #if canImport(UniformTypeIdentifiers)
    public var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .png: return .png
        case .tiff: return .tiff
        }
    }
    #endif

    /// Whether a lossy quality slider is meaningful for this format.
    public var supportsQuality: Bool {
        self == .jpeg || self == .heic
    }
}

/// User-chosen export options for the edited image.
public struct ExportSettings: Equatable, Sendable {
    public var format: ExportFormat = .jpeg
    /// Lossy compression quality, 0...1 (used for JPEG/HEIC).
    public var quality: Double = 0.9
    /// Optional resize: longest edge in pixels. `nil` keeps the original size.
    public var maxLongEdge: Int?

    public init(format: ExportFormat = .jpeg, quality: Double = 0.9, maxLongEdge: Int? = nil) {
        self.format = format
        self.quality = quality
        self.maxLongEdge = maxLongEdge
    }

    /// Common resize presets offered in the UI (nil = original).
    public static let resizePresets: [Int?] = [nil, 4096, 3000, 2048, 1600, 1080]
}
