import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Full-size image viewer shown on double-click. Supports left/right navigation,
/// zoom & pan, quick rating, delete (with confirm), and Esc to close.
struct PreviewView: View {
    @EnvironmentObject private var app: AppState
    let file: MediaFile

    @State private var image: NSImage?
    @State private var showDeleteConfirm = false

    // Zoom / pan state.
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private var index: Int? { app.displayedFiles.firstIndex(where: { $0.url == file.url }) }
    private var positionText: String {
        guard let index else { return "" }
        return "\(index + 1) / \(app.displayedFiles.count)"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()

            imageLayer

            navigationArrows

            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .task(id: file.url) {
            resetZoom()
            image = app.thumbnails.cachedImage(for: file.url)
            image = await app.thumbnails.previewImage(
                for: file.url,
                pixelSize: CGSize(width: 2600, height: 2600)
            )
        }
        .background(closeShortcut)
        .background(keyboardShortcuts)
        .confirmationDialog(
            "删除「\(file.name)」？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("移入废纸篓", role: .destructive) {
                Task { await app.performDeletion(app.planDeletion(for: [file.url])) }
            }
            Button("直接删除（不可恢复）", role: .destructive) {
                Task { await app.performDeletion(app.planDeletion(for: [file.url]), permanent: true) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if app.pairing.isPaired(file.url) {
                Text("将同时删除其配对文件，可用 ⌘Z 撤销。")
            } else {
                Text("可用 ⌘Z 撤销。")
            }
        }
    }

    // MARK: - Image + zoom

    @ViewBuilder
    private var imageLayer: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(zoom)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in zoom = clampZoom(baseZoom * value) }
                        .onEnded { _ in
                            baseZoom = zoom
                            if zoom <= 1 { resetPan() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard zoom > 1 else { return }
                            offset = CGSize(
                                width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in baseOffset = offset }
                )
                .onTapGesture(count: 2) { toggleZoom() }
                .padding(.horizontal, 64)
                .padding(.vertical, 88)
        } else {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat { min(max(value, 1), 6) }
    private func resetPan() { offset = .zero; baseOffset = .zero }
    private func resetZoom() { zoom = 1; baseZoom = 1; resetPan() }
    private func zoomIn() { zoom = clampZoom(zoom + 0.5); baseZoom = zoom }
    private func zoomOut() {
        zoom = clampZoom(zoom - 0.5); baseZoom = zoom
        if zoom <= 1 { resetPan() }
    }
    private func toggleZoom() {
        if zoom > 1 { resetZoom() } else { zoom = 2; baseZoom = 2 }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.headline)
                HStack(spacing: 8) {
                    if file.isRAW { Text("RAW").font(.caption.bold()) }
                    if app.pairing.isPaired(file.url) {
                        Label("含配对", systemImage: "link").font(.caption)
                    }
                    if let volume = file.volumeName {
                        Label(volume, systemImage: "sdcard").font(.caption)
                    }
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            ratingControl
            Button(action: app.closePreview) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .font(.title)
            .foregroundStyle(.white.opacity(0.85))
            .keyboardShortcut("w", modifiers: [.command])
            .help("关闭 (Esc)")
        }
        .foregroundStyle(.white)
        .padding()
        .background(LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
    }

    private var ratingControl: some View {
        let mark = app.mark(for: file)
        return HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= mark.rating.stars ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
                    .onTapGesture {
                        let new: Rating = (mark.rating.stars == star) ? .none : Rating(rawValue: star)!
                        app.setRating(new, for: file)
                    }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button(action: zoomOut) { Image(systemName: "minus.magnifyingglass") }
                .buttonStyle(.plain)
                .disabled(zoom <= 1)
            Text("\(Int(zoom * 100))%")
                .font(.callout.monospacedDigit())
                .frame(width: 48)
            Button(action: zoomIn) { Image(systemName: "plus.magnifyingglass") }
                .buttonStyle(.plain)
            Button("适应") { resetZoom() }
                .buttonStyle(.plain)
                .disabled(zoom == 1)

            Spacer()
            Text(positionText).font(.callout)
            Spacer()

            Button {
                app.openEditor(file.url)
            } label: {
                Label("编辑", systemImage: "slider.horizontal.3")
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("移入废纸篓", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
        .foregroundStyle(.white)
        .padding()
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }

    private var navigationArrows: some View {
        HStack {
            arrowButton("chevron.left") { app.previewStep(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled((index ?? 0) <= 0)
            Spacer()
            arrowButton("chevron.right") { app.previewStep(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled((index ?? 0) >= app.displayedFiles.count - 1)
        }
        .padding(.horizontal, 8)
    }

    private func arrowButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title)
                .foregroundStyle(.white)
                .padding(14)
                .background(.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hidden keyboard shortcuts

    private var closeShortcut: some View {
        Button("", action: app.closePreview)
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
    }

    private var keyboardShortcuts: some View {
        Group {
            ForEach(0...5, id: \.self) { rating in
                Button("") { app.setRating(Rating(rawValue: rating)!, for: file) }
                    .keyboardShortcut(KeyEquivalent(Character("\(rating)")), modifiers: [])
            }
            Button("") { app.toggleSelection(file.url, exclusive: false) }
                .keyboardShortcut(.space, modifiers: [])
            Button("", action: zoomIn).keyboardShortcut("=", modifiers: [.command])
            Button("", action: zoomOut).keyboardShortcut("-", modifiers: [.command])
            Button("", action: resetZoom).keyboardShortcut("0", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
