import Foundation

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

    public init() {}

    public static let identity = ImageAdjustments()

    /// True when nothing differs from the original image.
    public var isIdentity: Bool { self == .identity }
}
