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
#if canImport(Vision)
import Vision
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

    // MARK: - Geometry (rotate / straighten / flip / crop)

    /// Applies geometric edits in order: 90° rotation → horizontal flip →
    /// straighten (with auto-inscribe to drop empty corners) → user crop.
    static func applyGeometry(_ image: CIImage, _ adj: ImageAdjustments, includeCrop: Bool) -> CIImage {
        var img = image

        let quarters = ((adj.rotationQuarters % 4) + 4) % 4
        if quarters != 0 {
            img = img.transformed(by: CGAffineTransform(rotationAngle: -CGFloat(quarters) * .pi / 2))
            img = normalizeOrigin(img)
        }

        if adj.flipHorizontal {
            img = img.transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            img = normalizeOrigin(img)
        }

        if adj.straighten != 0 {
            let radians = CGFloat(adj.straighten) * .pi / 180
            let before = img.extent
            let center = CGPoint(x: before.midX, y: before.midY)
            var t = CGAffineTransform(translationX: center.x, y: center.y)
            t = t.rotated(by: radians)
            t = t.translatedBy(x: -center.x, y: -center.y)
            img = img.transformed(by: t)
            // Auto-inscribe a centered rect to remove the empty rotated corners.
            let inset = largestInscribedRect(width: before.width, height: before.height, angle: Double(radians))
            let rect = CGRect(
                x: img.extent.midX - inset.width / 2,
                y: img.extent.midY - inset.height / 2,
                width: inset.width,
                height: inset.height
            )
            img = normalizeOrigin(img.cropped(to: rect))
        }

        if includeCrop, let crop = adj.cropRect,
           crop != CGRect(x: 0, y: 0, width: 1, height: 1) {
            let e = img.extent
            let rect = CGRect(
                x: e.minX + crop.minX * e.width,
                y: e.minY + (1 - crop.maxY) * e.height, // top-left → bottom-left origin
                width: crop.width * e.width,
                height: crop.height * e.height
            ).integral
            img = normalizeOrigin(img.cropped(to: rect))
        }

        return img
    }

    private static func normalizeOrigin(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    /// Largest axis-aligned rectangle that fits inside a `w`×`h` rectangle
    /// rotated by `angle` (radians). Used to auto-crop after straightening.
    private static func largestInscribedRect(width w: CGFloat, height h: CGFloat, angle: Double) -> CGSize {
        guard w > 0, h > 0 else { return CGSize(width: max(w, 1), height: max(h, 1)) }
        let sinA = abs(sin(angle)), cosA = abs(cos(angle))
        let widthIsLonger = w >= h
        let sideLong = max(w, h), sideShort = min(w, h)
        var wr: CGFloat
        var hr: CGFloat
        if Double(sideShort) <= 2 * sinA * cosA * Double(sideLong) || abs(sinA - cosA) < 1e-10 {
            let x = 0.5 * sideShort
            if widthIsLonger {
                wr = sinA < 1e-9 ? sideLong : CGFloat(Double(x) / sinA)
                hr = cosA < 1e-9 ? sideShort : CGFloat(Double(x) / cosA)
            } else {
                wr = cosA < 1e-9 ? sideShort : CGFloat(Double(x) / cosA)
                hr = sinA < 1e-9 ? sideLong : CGFloat(Double(x) / sinA)
            }
        } else {
            let cos2 = cosA * cosA - sinA * sinA
            wr = CGFloat((Double(w) * cosA - Double(h) * sinA) / cos2)
            hr = CGFloat((Double(h) * cosA - Double(w) * sinA) / cos2)
        }
        return CGSize(width: max(1, min(wr, w)), height: max(1, min(hr, h)))
    }

    /// Detects the horizon and returns the straighten angle (degrees) needed to
    /// level it, or nil if no confident horizon was found.
    public func autoStraightenAngle(url: URL) async -> Double? {
        #if canImport(Vision)
        return await withCheckedContinuation { (cont: CheckedContinuation<Double?, Never>) in
            queue.async { [self] in
                guard let src = loadFullSource(url) else { cont.resume(returning: nil); return }
                let request = VNDetectHorizonRequest()
                let handler = VNImageRequestHandler(ciImage: src, options: [:])
                do {
                    try handler.perform([request])
                    if let obs = request.results?.first {
                        let degrees = Double(obs.angle) * 180 / .pi
                        cont.resume(returning: max(-45, min(45, -degrees)))
                    } else {
                        cont.resume(returning: nil)
                    }
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
        #else
        return nil
        #endif
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
    /// - Parameter includeCrop: when false, the user crop is skipped (used by the
    ///   crop UI, which needs the full straightened image to draw the crop box).
    public func renderPreview(
        url: URL,
        adjustments: ImageAdjustments,
        maxDimension: CGFloat,
        includeCrop: Bool = true
    ) async -> NSImage? {
        await withCheckedContinuation { cont in
            queue.async { [self] in
                guard let base = base(for: url, maxDimension: maxDimension) else {
                    cont.resume(returning: nil); return
                }
                let colored = ImagePipeline.apply(adjustments, to: base)
                let output = Self.applyGeometry(colored, adjustments, includeCrop: includeCrop)
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
                let colored = ImagePipeline.apply(adjustments, to: full)
                var output = Self.applyGeometry(colored, adjustments, includeCrop: true)
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
