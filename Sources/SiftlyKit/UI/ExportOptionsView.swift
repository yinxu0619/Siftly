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
            Label(L10n.exportTitle, systemImage: "square.and.arrow.down")
                .font(.title2.bold())

            Text(L10n.exportHint)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.format).font(.subheadline.bold())
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
                        Text(L10n.quality).font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(settings.quality * 100))%")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.quality, in: 0.3...1.0)
                    Text(L10n.qualityHint)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.resize).font(.subheadline.bold())
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
                    Text(L10n.exporting).font(.callout).foregroundStyle(.secondary)
                }
            }

            HStack {
                Button(L10n.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.saveAs) { saveAs() }
                    .disabled(app.isExporting)
                Button(L10n.exportToFolder) { exportToSourceFolder() }
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
        guard let value else { return L10n.originalSize }
        return L10n.longEdgePx(value)
    }

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
