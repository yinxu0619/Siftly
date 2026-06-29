import Foundation
import ImageIO

/// Basic EXIF information shown in the inspector. Read lazily and off the main
/// thread; never decodes full image data.
public struct EXIFInfo: Equatable {
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var iso: Int?
    public var aperture: Double?
    public var shutterSpeed: String?
    public var focalLength: Double?
    public var dateTaken: String?

    public init() {}

    public var dimensionDescription: String? {
        guard let w = pixelWidth, let h = pixelHeight else { return nil }
        return "\(w) × \(h)"
    }
}

public enum EXIFReader {
    public static func read(from url: URL) -> EXIFInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        var info = EXIFInfo()
        info.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
        info.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            info.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
            info.aperture = exif[kCGImagePropertyExifFNumber] as? Double
            info.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
            info.lensModel = exif[kCGImagePropertyExifLensModel] as? String
            info.dateTaken = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double {
                info.shutterSpeed = formatShutterSpeed(exposure)
            }
        }

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            info.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            info.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }

        return info
    }

    private static func formatShutterSpeed(_ exposure: Double) -> String {
        guard exposure > 0 else { return "—" }
        if exposure >= 1 {
            return String(format: "%.1fs", exposure)
        }
        return "1/\(Int((1.0 / exposure).rounded()))s"
    }
}
