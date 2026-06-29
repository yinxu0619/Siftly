import SwiftUI

/// A small, interactive RGB tone-curve editor. Press and drag anywhere on the
/// curve to reshape it — a control point is created under your cursor if there
/// isn't one already. Right-click a point to remove it. The two endpoints stay
/// pinned to the left/right edges (their height is still editable).
struct CurveEditorView: View {
    @Binding var curve: ToneCurve

    @State private var draggingIndex: Int?
    private let hitRadius: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.25))

                grid(in: size)

                curvePath(in: size)
                    .stroke(Color.white, lineWidth: 2)

                ForEach(curve.points.indices, id: \.self) { i in
                    let p = point(curve.points[i], in: size)
                    Circle()
                        .fill(draggingIndex == i ? Color.accentColor : Color.white)
                        .frame(width: 12, height: 12)
                        .position(p)
                        .contextMenu {
                            if i != 0 && i != curve.points.count - 1 {
                                Button("删除该点", role: .destructive) { removePoint(i) }
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture(in: size))
        }
        .frame(height: 180)
    }

    // MARK: - Geometry helpers

    private func point(_ normalized: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: (1 - normalized.y) * size.height)
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(location.x / size.width, 0), 1),
            y: min(max(1 - location.y / size.height, 0), 1)
        )
    }

    private func grid(in size: CGSize) -> some View {
        Path { path in
            for i in 1..<4 {
                let x = size.width * CGFloat(i) / 4
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * CGFloat(i) / 4
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
    }

    private func curvePath(in size: CGSize) -> Path {
        Path { path in
            let steps = 64
            for s in 0...steps {
                let x = Double(s) / Double(steps)
                let y = curve.sample(x)
                let pt = point(CGPoint(x: x, y: y), in: size)
                if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
        }
    }

    // MARK: - Interaction

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // On the first move, grab the nearest existing point, or create a
                // new one under the cursor so any spot on the curve is draggable.
                if draggingIndex == nil {
                    if let i = nearestPointIndex(to: value.startLocation, in: size) {
                        draggingIndex = i
                    } else {
                        draggingIndex = insertPoint(at: value.startLocation, in: size)
                    }
                }
                guard let i = draggingIndex else { return }
                var n = normalized(value.location, in: size)
                // Endpoints keep their x; interior points stay between neighbors.
                if i == 0 {
                    n.x = 0
                } else if i == curve.points.count - 1 {
                    n.x = 1
                } else {
                    let lo = curve.points[i - 1].x + 0.01
                    let hi = curve.points[i + 1].x - 0.01
                    n.x = min(max(n.x, lo), hi)
                }
                var pts = curve.points
                pts[i] = n
                curve = ToneCurve(points: pts)
            }
            .onEnded { _ in draggingIndex = nil }
    }

    /// Inserts a point at the cursor location and returns its index in the
    /// (sorted) points array.
    private func insertPoint(at location: CGPoint, in size: CGSize) -> Int {
        let n = normalized(location, in: size)
        var pts = curve.points
        let insertIndex = pts.firstIndex(where: { $0.x > n.x }) ?? pts.count
        pts.insert(n, at: insertIndex)
        curve = ToneCurve(points: pts)
        return insertIndex
    }

    private func nearestPointIndex(to location: CGPoint, in size: CGSize) -> Int? {
        var best: (index: Int, dist: CGFloat)?
        for i in curve.points.indices {
            let p = point(curve.points[i], in: size)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d <= hitRadius && (best == nil || d < best!.dist) {
                best = (i, d)
            }
        }
        return best?.index
    }

    private func removePoint(_ index: Int) {
        guard index > 0, index < curve.points.count - 1 else { return }
        var pts = curve.points
        pts.remove(at: index)
        curve = ToneCurve(points: pts)
    }
}
