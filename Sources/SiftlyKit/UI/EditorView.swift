import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Full-window, non-destructive image editor (Snapseed-style simple post). The
/// original card file is never touched — edits are rendered live and written to
/// a NEW file on export.
struct EditorView: View {
    @EnvironmentObject private var app: AppState
    let file: MediaFile

    @State private var adjustments = ImageAdjustments()
    @State private var preview: NSImage?
    @State private var original: NSImage?
    @State private var showOriginal = false
    @State private var sourceSize: CGSize?
    @State private var renderTask: Task<Void, Never>?
    @State private var isExportSheet = false

    // Crop / geometry state.
    @State private var cropMode = false
    @State private var cropDraft = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var cropImage: NSImage?
    @State private var cropAspect: CropAspect = .free
    @State private var autoLeveling = false

    private let previewMaxDimension: CGFloat = 1800
    private static let fullRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var body: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()
            HStack(spacing: 0) {
                previewArea
                Divider()
                controlPanel
                    .frame(width: 330)
                    .background(.bar)
            }
        }
        .task(id: file.url) { await loadInitial() }
        .onChange(of: adjustments) { _, _ in scheduleRender() }
        .onChange(of: adjustments.rotationQuarters) { _, _ in if cropMode { resetCropDraft(); renderCropImage() } }
        .onChange(of: adjustments.flipHorizontal) { _, _ in if cropMode { resetCropDraft(); renderCropImage() } }
        .onChange(of: adjustments.straighten) { _, _ in if cropMode { renderCropImage() } }
        .background(closeShortcut)
        .sheet(isPresented: $isExportSheet) {
            ExportOptionsView(source: file.url, adjustments: adjustments)
                .environmentObject(app)
        }
    }

    // MARK: - Preview

    private var previewArea: some View {
        ZStack {
            if cropMode {
                cropArea
            } else {
                normalPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var normalPreview: some View {
        ZStack {
            if let image = showOriginal ? original : preview {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(24)
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }

            if showOriginal {
                VStack {
                    Text(L10n.originalOverlay)
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 16)
                    Spacer()
                }
            }
        }
    }

    private var cropArea: some View {
        VStack(spacing: 0) {
            ZStack {
                if let cropImage {
                    CropOverlayView(image: cropImage, crop: $cropDraft, lockedNorm: cropLockedNorm)
                        .padding(24)
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            cropToolbar
        }
    }

    private var cropToolbar: some View {
        HStack(spacing: 12) {
            Button(L10n.cancel) { cropMode = false }
            Menu {
                ForEach(CropAspect.allCases, id: \.self) { a in
                    Button {
                        applyAspect(a)
                    } label: {
                        if a == cropAspect { Label(a.label, systemImage: "checkmark") } else { Text(a.label) }
                    }
                }
            } label: {
                Label(cropAspect.label, systemImage: "aspectratio")
            }
            .frame(width: 140)

            Button { rotate(-1) } label: { Image(systemName: "rotate.left") }
            Button { rotate(1) } label: { Image(systemName: "rotate.right") }

            Spacer()
            Button(L10n.done) { commitCrop() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Controls

    private var controlPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(L10n.sectionRotateCrop) {
                        HStack(spacing: 8) {
                            geoButton("rotate.left", L10n.rotateLeftHelp) { rotate(-1) }
                            geoButton("rotate.right", L10n.rotateRightHelp) { rotate(1) }
                            geoButton("arrow.left.and.right", L10n.flipHorizontalHelp, active: adjustments.flipHorizontal) {
                                adjustments.flipHorizontal.toggle()
                                adjustments.cropRect = nil
                            }
                            Spacer()
                            Button { beginCrop() } label: { Label(L10n.crop, systemImage: "crop") }
                        }
                        AdjustSlider(title: L10n.straighten, value: $adjustments.straighten, range: -45...45)
                        HStack {
                            Button { autoLevel() } label: {
                                Label(autoLeveling ? L10n.analyzing : L10n.autoLevel, systemImage: "level")
                            }
                            .disabled(autoLeveling)
                            Spacer()
                            if adjustments.hasGeometry {
                                Button(L10n.resetGeometry) { resetGeometry() }
                                    .font(.caption)
                            }
                        }
                    }
                    section(L10n.sectionLight) {
                        AdjustSlider(title: L10n.exposureAdj, value: $adjustments.exposure)
                        AdjustSlider(title: L10n.brightness, value: $adjustments.brightness)
                        AdjustSlider(title: L10n.contrast, value: $adjustments.contrast)
                        AdjustSlider(title: L10n.highlights, value: $adjustments.highlights)
                        AdjustSlider(title: L10n.shadows, value: $adjustments.shadows)
                        AdjustSlider(title: L10n.hdr, value: $adjustments.hdr, range: 0...100)
                    }
                    section(L10n.sectionColor) {
                        AdjustSlider(title: L10n.saturation, value: $adjustments.saturation)
                        AdjustSlider(title: L10n.vibrance, value: $adjustments.vibrance)
                        AdjustSlider(title: L10n.temperature, value: $adjustments.temperature)
                        AdjustSlider(title: L10n.tint, value: $adjustments.tint)
                    }
                    section(L10n.sectionDetail) {
                        AdjustSlider(title: L10n.sharpen, value: $adjustments.sharpen, range: 0...100)
                        AdjustSlider(title: L10n.vignette, value: $adjustments.vignette, range: 0...100)
                    }
                    section(L10n.sectionCurve) {
                        CurveEditorView(curve: $adjustments.curve)
                        HStack {
                            Text(L10n.curveHint)
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.resetCurve) { adjustments.curve = .identity }
                                .font(.caption)
                                .disabled(adjustments.curve.isIdentity)
                        }
                    }
                }
                .padding()
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).font(.headline).lineLimit(1).truncationMode(.middle)
                if let s = sourceSize {
                    Text("\(Int(s.width)) × \(Int(s.height))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: app.closeEditor) {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("w", modifiers: [.command])
            .help(L10n.closeHelp)
        }
        .padding()
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                adjustments = .identity
            } label: {
                Label(L10n.resetAll, systemImage: "arrow.uturn.backward")
            }
            .disabled(adjustments.isIdentity)

            Label(L10n.compare, systemImage: "circle.lefthalf.filled")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(showOriginal ? Color.accentColor : Color.secondary)
                .help(L10n.compareHelp)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in showOriginal = true }
                        .onEnded { _ in showOriginal = false }
                )

            Spacer()

            Button {
                isExportSheet = true
            } label: {
                Label(L10n.export, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.isExporting)
        }
        .padding()
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            content()
        }
    }

    private func geoButton(_ systemName: String, _ help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.bordered)
        .tint(active ? .accentColor : nil)
        .help(help)
    }

    // MARK: - Geometry actions

    private func rotate(_ direction: Int) {
        adjustments.rotationQuarters = (((adjustments.rotationQuarters + direction) % 4) + 4) % 4
        adjustments.cropRect = nil
    }

    private func resetGeometry() {
        adjustments.rotationQuarters = 0
        adjustments.straighten = 0
        adjustments.flipHorizontal = false
        adjustments.cropRect = nil
    }

    private func autoLevel() {
        autoLeveling = true
        Task {
            let angle = await app.processor.autoStraightenAngle(url: file.url)
            autoLeveling = false
            if let angle { adjustments.straighten = angle }
        }
    }

    // MARK: - Crop

    private func beginCrop() {
        cropDraft = adjustments.cropRect ?? Self.fullRect
        cropAspect = .free
        cropMode = true
        renderCropImage()
    }

    private func commitCrop() {
        let r = cropDraft
        let isFull = r.minX < 0.001 && r.minY < 0.001 && r.width > 0.999 && r.height > 0.999
        adjustments.cropRect = isFull ? nil : r
        cropMode = false
    }

    private func resetCropDraft() {
        cropDraft = Self.fullRect
        cropAspect = .free
    }

    private func renderCropImage() {
        let current = adjustments
        Task {
            let img = await app.processor.renderPreview(
                url: file.url, adjustments: current, maxDimension: previewMaxDimension, includeCrop: false
            )
            cropImage = img
        }
    }

    private var cropLockedNorm: CGFloat? { lockedNorm(for: cropAspect) }

    private func lockedNorm(for a: CropAspect) -> CGFloat? {
        switch a {
        case .free:
            return nil
        case .original:
            return 1
        default:
            guard let t = a.ratio, let img = cropImage else { return nil }
            let ar = img.size.width / max(img.size.height, 1)
            return t / ar
        }
    }

    private func applyAspect(_ a: CropAspect) {
        cropAspect = a
        guard let norm = lockedNorm(for: a) else { return }
        var w: CGFloat = 1
        var h: CGFloat = 1
        if norm >= 1 { w = 1; h = 1 / norm } else { h = 1; w = norm }
        cropDraft = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    private enum CropAspect: CaseIterable {
        case free, original, square, r3_2, r2_3, r4_3, r3_4, r16_9

        var label: String {
            switch self {
            case .free: return L10n.cropFree
            case .original: return L10n.cropOriginal
            case .square: return "1:1"
            case .r3_2: return "3:2"
            case .r2_3: return "2:3"
            case .r4_3: return "4:3"
            case .r3_4: return "3:4"
            case .r16_9: return "16:9"
            }
        }

        /// Pixel aspect (width / height); nil for free/original.
        var ratio: CGFloat? {
            switch self {
            case .free, .original: return nil
            case .square: return 1
            case .r3_2: return 3.0 / 2.0
            case .r2_3: return 2.0 / 3.0
            case .r4_3: return 4.0 / 3.0
            case .r3_4: return 3.0 / 4.0
            case .r16_9: return 16.0 / 9.0
            }
        }
    }

    // MARK: - Rendering

    private func loadInitial() async {
        sourceSize = await app.processor.sourcePixelSize(file.url)
        let base = await app.processor.renderPreview(
            url: file.url, adjustments: .identity, maxDimension: previewMaxDimension
        )
        original = base
        if adjustments.isIdentity {
            preview = base
        } else {
            scheduleRender()
        }
    }

    private func scheduleRender() {
        renderTask?.cancel()
        let current = adjustments
        renderTask = Task {
            try? await Task.sleep(nanoseconds: 70_000_000)
            if Task.isCancelled { return }
            let img = await app.processor.renderPreview(
                url: file.url, adjustments: current, maxDimension: previewMaxDimension
            )
            if Task.isCancelled { return }
            preview = img
        }
    }

    private var closeShortcut: some View {
        Button("", action: app.closeEditor)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
    }
}

/// A single labeled adjustment slider with an inline reset affordance.
private struct AdjustSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = -100...100
    var defaultValue: Double = 0

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Text(title).font(.callout)
                Spacer()
                if value != defaultValue {
                    Button {
                        value = defaultValue
                    } label: {
                        Image(systemName: "arrow.uturn.backward").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Text("\(Int(value))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            Slider(value: $value, in: range)
        }
    }
}
