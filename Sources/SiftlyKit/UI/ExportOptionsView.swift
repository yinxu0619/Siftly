import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Export options for an edited image: format conversion, compression quality,
/// and optional resize. Always writes a NEW file.
struct ExportOptionsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let source: URL
    let adjustments: ImageAdjustments

    @State private var settings = ExportSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("导出编辑结果", systemImage: "square.and.arrow.down")
                .font(.title2.bold())

            Text("原图不会被修改，编辑结果会保存为新文件。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("格式").font(.subheadline.bold())
                Picker("", selection: $settings.format) {
                    ForEach(ExportFormat.allCases) { fmt in
                        Text(fmt.title).tag(fmt)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if settings.format.supportsQuality {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("质量").font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(settings.quality * 100))%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.quality, in: 0.3...1.0)
                    Text("数值越低文件越小，画质损失越多。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("尺寸").font(.subheadline.bold())
                Picker("", selection: resizeBinding) {
                    ForEach(ExportSettings.resizePresets.indices, id: \.self) { i in
                        Text(resizeLabel(ExportSettings.resizePresets[i]))
                            .tag(ExportSettings.resizePresets[i])
                    }
                }
                .labelsHidden()
            }

            if app.isExporting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在导出…").font(.callout).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("另存为…") { saveAs() }
                    .disabled(app.isExporting)
                Button("导出到原文件夹") { exportToSourceFolder() }
                    .buttonStyle(.borderedProminent)
                    .disabled(app.isExporting)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var resizeBinding: Binding<Int?> {
        Binding(get: { settings.maxLongEdge }, set: { settings.maxLongEdge = $0 })
    }

    private func resizeLabel(_ value: Int?) -> String {
        guard let value else { return "原始尺寸" }
        return "长边 \(value) px"
    }

    // MARK: - Actions

    private func exportToSourceFolder() {
        let dest = app.suggestedExportURL(for: source, format: settings.format)
        runExport(to: dest)
    }

    private func saveAs() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        let suggested = app.suggestedExportURL(for: source, format: settings.format)
        panel.directoryURL = source.deletingLastPathComponent()
        panel.nameFieldStringValue = suggested.lastPathComponent
        #if canImport(UniformTypeIdentifiers)
        panel.allowedContentTypes = [settings.format.utType]
        #endif
        if panel.runModal() == .OK, let url = panel.url {
            runExport(to: url)
        }
        #endif
    }

    private func runExport(to dest: URL) {
        let s = settings
        let a = adjustments
        let src = source
        Task {
            let url = await app.exportEdited(source: src, adjustments: a, settings: s, to: dest)
            if let url {
                app.revealInFinder(url)
                dismiss()
            }
        }
    }
}
