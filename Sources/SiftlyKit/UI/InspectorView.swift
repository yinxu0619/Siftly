import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var app: AppState
    @State private var exif: EXIFInfo?
    @State private var isLoadingEXIF = false

    private var current: MediaFile? {
        guard let url = app.currentFileURL else { return nil }
        return app.files.first { $0.url == url }
    }

    var body: some View {
        Group {
            if let file = current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        fileSection(file)
                        markSection(file)
                        exifSection
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView("未选择文件", systemImage: "info.circle")
            }
        }
        .navigationTitle("信息")
        .task(id: app.currentFileURL) {
            await loadEXIF()
        }
    }

    private func fileSection(_ file: MediaFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.name).font(.headline).textSelection(.enabled)
            if let size = file.fileSize {
                infoRow("大小", ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
            if let date = file.modificationDate {
                infoRow("修改时间", date.formatted(date: .abbreviated, time: .shortened))
            }
            infoRow("格式", file.ext.uppercased())
            if app.pairing.isPaired(file.url) {
                let partners = app.pairing.partners(of: file.url)
                    .map { $0.lastPathComponent }
                    .sorted()
                    .joined(separator: ", ")
                infoRow("配对", partners)
            }
        }
    }

    private func markSection(_ file: MediaFile) -> some View {
        let mark = app.mark(for: file)
        return VStack(alignment: .leading, spacing: 8) {
            Text("标记").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= mark.rating.stars ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                        .onTapGesture {
                            let new: Rating = (mark.rating.stars == star) ? .none : Rating(rawValue: star)!
                            app.setRating(new, for: file)
                        }
                }
            }
            HStack(spacing: 6) {
                ForEach(ColorLabel.allCases) { label in
                    Circle()
                        .fill(label == .none ? Color.secondary.opacity(0.2) : label.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if mark.label == label {
                                Circle().strokeBorder(Color.primary, lineWidth: 2)
                            }
                            if label == .none {
                                Image(systemName: "slash.circle").font(.system(size: 10))
                            }
                        }
                        .onTapGesture { app.setLabel(label, for: file) }
                }
            }
        }
    }

    @ViewBuilder
    private var exifSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXIF").font(.subheadline).foregroundStyle(.secondary)
            if isLoadingEXIF {
                ProgressView().controlSize(.small)
            } else if let exif {
                if let dim = exif.dimensionDescription { infoRow("尺寸", dim) }
                if let model = exif.cameraModel { infoRow("相机", model) }
                if let lens = exif.lensModel { infoRow("镜头", lens) }
                if let iso = exif.iso { infoRow("ISO", "\(iso)") }
                if let f = exif.aperture { infoRow("光圈", String(format: "f/%.1f", f)) }
                if let s = exif.shutterSpeed { infoRow("快门", s) }
                if let fl = exif.focalLength { infoRow("焦距", String(format: "%.0fmm", fl)) }
                if let date = exif.dateTaken { infoRow("拍摄时间", date) }
            } else {
                Text("无 EXIF 信息").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func loadEXIF() async {
        guard let file = current else { exif = nil; return }
        isLoadingEXIF = true
        let url = file.url
        let result = await Task.detached(priority: .utility) {
            EXIFReader.read(from: url)
        }.value
        if app.currentFileURL == url {
            exif = result
            isLoadingEXIF = false
        }
    }
}
