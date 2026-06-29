import Foundation
#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
#endif
#if canImport(AppKit)
import AppKit
#endif

public enum ImageProcessingError: Error {
    case cannotLoadSource
    case renderFailed
    case writeFailed
}

#if canImport(CoreImage)

/// Loads, renders, and exports images for the non-destructive editor. Holds a
/// single reusable `CIContext` and caches the developed source so live slider
/// edits only re-run the (cheap) filter chain, not the RAW decode. All heavy
/// work is meant to run off the main actor.
public final class ImageProcessor: @unchecked Sendable {
    private let context: CIContext
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private let queue = DispatchQueue(label: "com.siftly.imageprocessor", qos: .userInitiated)

    private let lock = NSLock()
    private var sourceURL: URL?
    private var fullSource: CIImage?
    private var previewBase: CIImage?
    private var previewDim: CGFloat = 0

    public init() {
        context = CIContext(options: [.useSoftwareRenderer: false])
    }

    // MARK: - Source loading

    /// Develops the source image: RAW files go through `CIRAWFilter`; everything
    /// else is loaded with embedded orientation applied. Result is cached.
    private func loadFullSource(_ url: URL) -> CIImage? {
        lock.lock()
        if sourceURL == url, let cached = fullSource { lock.unlock(); return cached }
        lock.unlock()

        let developed = Self.develop(url)

        lock.lock()
        sourceURL = url
        fullSource = developed
        previewBase = nil
        previewDim = 0
        lock.unlock()
        return developed
    }

    private static func develop(_ url: URL) -> CIImage? {
        let ext = url.pathExtension.lowercased()
        if MediaCatalog.rawExtensions.contains(ext) {
            if let raw = CIRAWFilter(imageURL: url), let out = raw.outputImage {
                return out
            }
        }
        return CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
    }

    /// A downscaled copy of the source for responsive live preview rendering.
    private func base(for url: URL, maxDimension: CGFloat) -> CIImage? {
        lock.lock()
        if sourceURL == url, let base = previewBase, previewDim == maxDimension {
            lock.unlock(); return base
        }
        lock.unlock()

        guard let full = loadFullSource(url) else { return nil }
        let scaled = Self.scaled(full, maxLongEdge: maxDimension)

        lock.lock()
        previewBase = scaled
        previewDim = maxDimension
        lock.unlock()
        return scaled
    }

    private static func scaled(_ image: CIImage, maxLongEdge: CGFloat) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > maxLongEdge, longest > 0 else { return image }
        let scale = maxLongEdge / longest
        let f = CIFilter.lanczosScaleTransform()
        f.inputImage = image
        f.scale = Float(scale)
        f.aspectRatio = 1
        return f.outputImage ?? image
    }

    // MARK: - Rendering

    /// The pixel size of the developed source (post-orientation), if available.
    public func sourcePixelSize(_ url: URL) async -> CGSize? {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                cont.resume(returning: loadFullSource(url).map { $0.extent.size })
            }
        }
    }

    #if canImport(AppKit)
    /// Renders a live preview (downscaled) with the given adjustments.
    public func renderPreview(url: URL, adjustments: ImageAdjustments, maxDimension: CGFloat) async -> NSImage? {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                guard let base = base(for: url, maxDimension: maxDimension) else {
                    cont.resume(returning: nil); return
                }
                let output = ImagePipeline.apply(adjustments, to: base)
                guard let cg = context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: sRGB) else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
            }
        }
    }
    #endif

    // MARK: - Export

    /// Renders at full resolution and writes the result to `destination`.
    public func export(
        url: URL,
        adjustments: ImageAdjustments,
        settings: ExportSettings,
        to destination: URL
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let full = loadFullSource(url) else {
                    cont.resume(throwing: ImageProcessingError.cannotLoadSource); return
                }
                var output = ImagePipeline.apply(adjustments, to: full)
                if let maxEdge = settings.maxLongEdge {
                    output = Self.scaled(output, maxLongEdge: CGFloat(maxEdge))
                }
                output = output.cropped(to: output.extent)
                do {
                    try write(output, to: destination, settings: settings)
                    cont.resume(returning: ())
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func write(_ image: CIImage, to url: URL, settings: ExportSettings) throws {
        let qualityOptions: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): settings.quality
        ]
        switch settings.format {
        case .jpeg:
            try context.writeJPEGRepresentation(of: image, to: url, colorSpace: sRGB, options: qualityOptions)
        case .heic:
            try context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: sRGB, options: qualityOptions)
        case .png:
            try context.writePNGRepresentation(of: image, to: url, format: .RGBA8, colorSpace: sRGB, options: [:])
        case .tiff:
            try context.writeTIFFRepresentation(of: image, to: url, format: .RGBA8, colorSpace: sRGB, options: [:])
        }
    }
}

#else

/// Non-Apple placeholder so the package still type-checks where Core Image is
/// unavailable. The editor UI is macOS-only.
public final class ImageProcessor: @unchecked Sendable {
    public init() {}
}

#endif
