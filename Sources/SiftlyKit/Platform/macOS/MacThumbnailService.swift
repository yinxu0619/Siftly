#if os(macOS)
import Foundation
import CoreGraphics
import ImageIO
import QuickLookThumbnailing

/// Thumbnail generation backed by QuickLook (great RAW support) with an ImageIO
/// fallback for formats QuickLook may decline.
public final class MacThumbnailService: ThumbnailService {
    public init() {}

    public func thumbnail(for url: URL, size: CGSize) async -> CGImage? {
        let scale: CGFloat = 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return rep.cgImage
        }

        let maxPixel = Int(max(size.width, size.height) * scale)
        return Self.imageIOThumbnail(for: url, maxPixel: maxPixel)
    }

    private static func imageIOThumbnail(for url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
#endif
