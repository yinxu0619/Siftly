import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Interactive crop overlay drawn on top of the (already rotated/straightened)
/// image. The crop rect is kept in normalized coordinates (0...1, top-left
/// origin) relative to the displayed image.
struct CropOverlayView: View {
    let image: NSImage
    @Binding var crop: CGRect
    /// Optional locked aspect (crop.width / crop.height in normalized space).
    /// nil means free-form.
    var lockedNorm: CGFloat?

    @State private var dragStart: CGRect?

    private let minSize: CGFloat = 0.06
    private let handle: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let fit = fittedRect(in: geo.size)

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)

                // Dim everything outside the crop rect.
                let box = viewRect(in: fit)
                Path { p in
                    p.addRect(fit)
                    p.addRect(box)
                }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                gridAndBorder(box)

                // Move gesture over the interior.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
                    .gesture(moveGesture(fit: fit))

                cornerHandles(box: box, fit: fit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: - Drawing

    private func gridAndBorder(_ box: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: box.width, height: box.height)
                .position(x: box.midX, y: box.midY)
            ForEach(1..<3) { i in
                let f = CGFloat(i) / 3
                Path { p in
                    p.move(to: CGPoint(x: box.minX + box.width * f, y: box.minY))
                    p.addLine(to: CGPoint(x: box.minX + box.width * f, y: box.maxY))
                    p.move(to: CGPoint(x: box.minX, y: box.minY + box.height * f))
                    p.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * f))
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerHandles(box: CGRect, fit: CGRect) -> some View {
        ForEach(Corner.allCases, id: \.self) { corner in
            let pt = corner.point(in: box)
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                .frame(width: handle, height: handle)
                .contentShape(Rectangle())
                .position(x: pt.x, y: pt.y)
                .gesture(cornerGesture(corner, fit: fit))
        }
    }

    // MARK: - Geometry helpers

    private func fittedRect(in size: CGSize) -> CGRect {
        let iw = max(image.size.width, 1)
        let ih = max(image.size.height, 1)
        let ar = iw / ih
        var w = size.width
        var h = w / ar
        if h > size.height {
            h = size.height
            w = h * ar
        }
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }

    private func viewRect(in fit: CGRect) -> CGRect {
        CGRect(
            x: fit.minX + crop.minX * fit.width,
            y: fit.minY + crop.minY * fit.height,
            width: crop.width * fit.width,
            height: crop.height * fit.height
        )
    }

    // MARK: - Gestures

    private func moveGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = crop }
                let dx = value.translation.width / fit.width
                let dy = value.translation.height / fit.height
                var r = start
                r.origin.x = min(max(0, start.minX + dx), 1 - start.width)
                r.origin.y = min(max(0, start.minY + dy), 1 - start.height)
                crop = r
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cornerGesture(_ corner: Corner, fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = crop }
                let dx = value.translation.width / fit.width
                let dy = value.translation.height / fit.height
                crop = resize(start, corner: corner, dx: dx, dy: dy)
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resize(_ start: CGRect, corner: Corner, dx: CGFloat, dy: CGFloat) -> CGRect {
        var minX = start.minX, minY = start.minY, maxX = start.maxX, maxY = start.maxY
        switch corner {
        case .topLeft: minX += dx; minY += dy
        case .topRight: maxX += dx; minY += dy
        case .bottomLeft: minX += dx; maxY += dy
        case .bottomRight: maxX += dx; maxY += dy
        }
        minX = min(max(0, minX), maxX - minSize)
        maxX = max(min(1, maxX), minX + minSize)
        minY = min(max(0, minY), maxY - minSize)
        maxY = max(min(1, maxY), minY + minSize)
        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        if let aspect = lockedNorm, aspect > 0 {
            // Anchor the corner opposite to the one being dragged.
            let anchor = corner.opposite.point(in: CGRect(x: 0, y: 0, width: 1, height: 1))
            var w = rect.width
            var h = w / aspect
            if h > 1 { h = 1; w = h * aspect }
            // Drive size by the dimension that changed most.
            if abs(dx) < abs(dy) {
                h = rect.height
                w = h * aspect
            }
            w = min(w, 1)
            h = min(h, 1)
            let ox = anchor.x == 0 ? rect.minX : rect.maxX - w
            let oy = anchor.y == 0 ? rect.minY : rect.maxY - h
            rect = CGRect(x: min(max(0, ox), 1 - w), y: min(max(0, oy), 1 - h), width: w, height: h)
        }
        return rect
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        func point(in box: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: box.minX, y: box.minY)
            case .topRight: return CGPoint(x: box.maxX, y: box.minY)
            case .bottomLeft: return CGPoint(x: box.minX, y: box.maxY)
            case .bottomRight: return CGPoint(x: box.maxX, y: box.maxY)
            }
        }

        var opposite: Corner {
            switch self {
            case .topLeft: return .bottomRight
            case .topRight: return .bottomLeft
            case .bottomLeft: return .topRight
            case .bottomRight: return .topLeft
            }
        }
    }
}
