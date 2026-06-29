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

    private let previewMaxDimension: CGFloat = 1800

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
        .background(closeShortcut)
        .sheet(isPresented: $isExportSheet) {
            ExportOptionsView(source: file.url, adjustments: adjustments)
                .environmentObject(app)
        }
    }

    // MARK: - Preview

    private var previewArea: some View {
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
                    Text("原图")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 16)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Controls

    private var controlPanel: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("光效") {
                        AdjustSlider(title: "曝光", value: $adjustments.exposure)
                        AdjustSlider(title: "亮度", value: $adjustments.brightness)
                        AdjustSlider(title: "对比度", value: $adjustments.contrast)
                        AdjustSlider(title: "高光", value: $adjustments.highlights)
                        AdjustSlider(title: "阴影", value: $adjustments.shadows)
                        AdjustSlider(title: "HDR", value: $adjustments.hdr, range: 0...100)
                    }
                    section("色彩") {
                        AdjustSlider(title: "饱和度", value: $adjustments.saturation)
                        AdjustSlider(title: "自然饱和度", value: $adjustments.vibrance)
                        AdjustSlider(title: "色温", value: $adjustments.temperature)
                        AdjustSlider(title: "色调", value: $adjustments.tint)
                    }
                    section("细节") {
                        AdjustSlider(title: "锐化", value: $adjustments.sharpen, range: 0...100)
                        AdjustSlider(title: "暗角", value: $adjustments.vignette, range: 0...100)
                    }
                    section("曲线") {
                        CurveEditorView(curve: $adjustments.curve)
                        HStack {
                            Text("在曲线上按住拖动即可调整 · 右键点可删除")
                                .font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Button("重置曲线") { adjustments.curve = .identity }
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
            .help("关闭 (Esc)")
        }
        .padding()
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                adjustments = .identity
            } label: {
                Label("重置全部", systemImage: "arrow.uturn.backward")
            }
            .disabled(adjustments.isIdentity)

            // Press & hold to compare with the original.
            Label("对比", systemImage: "circle.lefthalf.filled")
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(showOriginal ? Color.accentColor : Color.secondary)
                .help("按住对比原图")
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in showOriginal = true }
                        .onEnded { _ in showOriginal = false }
                )

            Spacer()

            Button {
                isExportSheet = true
            } label: {
                Label("导出", systemImage: "square.and.arrow.down")
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
