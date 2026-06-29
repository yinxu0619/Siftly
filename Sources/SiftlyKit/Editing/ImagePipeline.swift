import Foundation
#if canImport(CoreImage)
import CoreImage
import CoreImage.CIFilterBuiltins

/// Maps `ImageAdjustments` (friendly UI units) onto a Core Image filter chain.
/// Each stage is skipped when its control is at the neutral value, both for
/// performance and to avoid unnecessary precision loss.
public enum ImagePipeline {
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func apply(_ adj: ImageAdjustments, to input: CIImage) -> CIImage {
        var image = input

        // 1. Exposure (EV).
        if adj.exposure != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = image
            f.ev = Float(adj.exposure / 100.0 * 2.0)
            image = f.outputImage ?? image
        }

        // 2. Highlights / shadows (+ HDR shadow lift / highlight recovery).
        let hdrK = adj.hdr / 100.0
        let shadowAmount = clamp(adj.shadows / 100.0 + hdrK * 0.6, -1, 1)
        // highlightAmount: 1.0 = unchanged, lower darkens/recovers highlights.
        let highlightAmount = clamp(1.0 + min(0, adj.highlights) / 100.0 * 0.8 - hdrK * 0.5, 0, 1)
        if shadowAmount != 0 || highlightAmount != 1 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = image
            f.radius = 8
            f.shadowAmount = Float(shadowAmount)
            f.highlightAmount = Float(highlightAmount)
            image = f.outputImage ?? image
        }
        // Brighten highlights (positive) via a soft exposure on the upper range
        // is non-trivial; for simple editing positive highlights nudges contrast.

        // 3. White balance (temperature / tint).
        if adj.temperature != 0 || adj.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 + adj.temperature * 30, y: adj.tint)
            image = f.outputImage ?? image
        }

        // 4. Brightness / contrast / saturation.
        if adj.brightness != 0 || adj.contrast != 0 || adj.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.brightness = Float(adj.brightness / 100.0 * 0.3)
            f.contrast = Float(1.0 + adj.contrast / 100.0 * 0.5)
            f.saturation = Float(1.0 + adj.saturation / 100.0)
            image = f.outputImage ?? image
        }

        // 5. Vibrance.
        if adj.vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = image
            f.amount = Float(adj.vibrance / 100.0)
            image = f.outputImage ?? image
        }

        // 6. Tone curve (RGB master).
        if !adj.curve.isIdentity {
            let f = CIFilter.colorCurves()
            f.inputImage = image
            f.curvesData = adj.curve.curvesData()
            f.curvesDomain = CIVector(x: 0, y: 1)
            f.colorSpace = sRGB
            image = f.outputImage ?? image
        }

        // 7. HDR local-contrast pop (unsharp mask at a large radius).
        if hdrK > 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = image
            f.radius = 12
            f.intensity = Float(hdrK * 0.8)
            image = f.outputImage ?? image
        }

        // 8. Sharpen (detail).
        if adj.sharpen > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(adj.sharpen / 100.0)
            image = f.outputImage ?? image
        }

        // 9. Vignette.
        if adj.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = image
            f.intensity = Float(adj.vignette / 100.0 * 1.5)
            f.radius = 1.5
            image = f.outputImage ?? image
        }

        // Keep the output extent equal to the source (some filters can shift it).
        return image.cropped(to: input.extent)
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
#endif
