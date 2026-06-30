import Foundation
import CoreGraphics

/// All non-destructive adjustments applied to an image. Values use friendly UI
/// units (mostly -100...100, or 0...100 for one-directional effects) which the
/// pipeline maps to the underlying Core Image parameter ranges.
public struct ImageAdjustments: Equatable, Codable, Sendable {
    /// Light
    public var exposure: Double = 0     // -100...100  -> EV -2...2
    public var brightness: Double = 0   // -100...100
    public var contrast: Double = 0     // -100...100
    public var highlights: Double = 0   // -100...100 (negative recovers highlights)
    public var shadows: Double = 0      // -100...100 (positive lifts shadows)
    public var hdr: Double = 0          // 0...100 (local tone + contrast pop)

    /// Color
    public var saturation: Double = 0   // -100...100
    public var vibrance: Double = 0     // -100...100
    public var temperature: Double = 0  // -100...100 (negative cooler, positive warmer)
    public var tint: Double = 0         // -100...100 (negative green, positive magenta)

    /// Detail
    public var sharpen: Double = 0      // 0...100
    public var vignette: Double = 0     // 0...100

    /// Tone curve (RGB master).
    public var curve: ToneCurve = .identity

    /// Geometry
    public var rotationQuarters: Int = 0   // number of clockwise 90° turns (0...3)
    public var straighten: Double = 0      // fine leveling, degrees, -45...45
    public var flipHorizontal: Bool = false
    /// Normalized crop rect (0...1, top-left origin) in the rotated/straightened
    /// image space. `nil` means the full frame.
    public var cropRect: CGRect?

    public init() {}

    public static let identity = ImageAdjustments()

    /// True when nothing differs from the original image.
    public var isIdentity: Bool { self == .identity }

    /// True when any geometry (rotate / straighten / flip / crop) is applied.
    public var hasGeometry: Bool {
        rotationQuarters % 4 != 0 || straighten != 0 || flipHorizontal || cropRect != nil
    }
}
