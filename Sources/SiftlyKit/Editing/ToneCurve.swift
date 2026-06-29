import Foundation
import CoreGraphics

/// A simple, Snapseed-style tone curve described by control points in the
/// normalized 0...1 input/output space. Points are kept sorted by x. The first
/// and last points anchor the curve at the shadow (x=0) and highlight (x=1)
/// edges. Applied to all RGB channels equally (a luminance/RGB master curve).
public struct ToneCurve: Equatable, Codable, Sendable {
    public var points: [CGPoint]

    public init(points: [CGPoint]) {
        self.points = points.sorted { $0.x < $1.x }
    }

    /// Straight line y = x (no change).
    public static let identity = ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)])

    public var isIdentity: Bool { self == .identity }

    /// Linearly interpolated output for a given normalized input (0...1).
    public func sample(_ x: Double) -> Double {
        guard let first = points.first, let last = points.last else { return x }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            if x <= b.x {
                let span = b.x - a.x
                guard span > 0 else { return a.y }
                let t = (x - a.x) / span
                return a.y + (b.y - a.y) * t
            }
        }
        return last.y
    }

    /// Packs the curve as interleaved RGB Float32 samples for `CIColorCurves`.
    /// Each of `count` samples carries identical R/G/B values.
    public func curvesData(count: Int = 128) -> Data {
        var floats = [Float]()
        floats.reserveCapacity(count * 3)
        for i in 0..<count {
            let x = Double(i) / Double(count - 1)
            let y = Float(min(max(sample(x), 0), 1))
            floats.append(y) // R
            floats.append(y) // G
            floats.append(y) // B
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
