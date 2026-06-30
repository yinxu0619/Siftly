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

    // EXIF overlay (persisted toggle, can be turned off).
    @AppStorage("siftly.preview.showEXIF") private var showEXIF = true
    @State private var exif: EXIFInfo?

    // Zoom / pan state.
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    // Scroll-wheel navigation throttling.
    @State private var scrollAccumulator: CGFloat = 0
    @State private var lastScrollStep = Date.distantPast

    private var index: Int? { app.displayedFiles.firstIndex(where: { $0.url == file.url }) }
    private var positionText: String {
        guard let index else { return "" }
        return "\(index + 1) / \(app.displayedFiles.count)"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()

            ScrollWheelCatcher { delta in handleScroll(delta) }

            imageLayer

            navigationArrows

            VStack {
                topBar
                Spacer()
                bottomBar
            }

            if showEXIF {
                exifOverlay
            }
        }
        .task(id: file.url) {
            resetZoom()
            let url = file.url
            image = app.thumbnails.cachedImage(for: url)
            let loaded = await app.thumbnails.previewImage(for: url, pixelSize: AppState.previewPixelSize)
            if !Task.isCancelled { image = loaded }
            app.prefetchAdjacentPreviews(around: url)
        }
        .task(id: file.url) {
            exif = nil
            let url = file.url
            let result = await Task.detached(priority: .utility) { EXIFReader.read(from: url) }.value
            if file.url == url { exif = result }
        }
        .background(closeShortcut)
        .background(keyboardShortcuts)
        .confirmationDialog(
            L10n.deleteConfirmTitle(file.name),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.moveToTrash, role: .destructive) {
                Task { await app.performDeletion(app.planDeletion(for: [file.url])) }
            }
            Button(L10n.deletePermanentPreview, role: .destructive) {
                Task { await app.performDeletion(app.planDeletion(for: [file.url]), permanent: true) }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            if app.pairing.isPaired(file.url) {
                Text(L10n.deleteWithPairingUndo)
            } else {
                Text(L10n.deleteUndoHint)
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

    /// Mouse-wheel / two-finger scroll switches photos when not zoomed in.
    private func handleScroll(_ delta: CGFloat) {
        guard zoom <= 1, delta != 0 else { return }
        let now = Date()
        if now.timeIntervalSince(lastScrollStep) > 0.4 { scrollAccumulator = 0 }
        scrollAccumulator += delta
        guard abs(scrollAccumulator) >= 6 else { return }
        guard now.timeIntervalSince(lastScrollStep) >= 0.12 else { return }
        let step = scrollAccumulator > 0 ? -1 : 1   // scroll up → previous, down → next
        scrollAccumulator = 0
        lastScrollStep = now
        app.previewStep(step)
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.headline)
                HStack(spacing: 8) {
                    if file.isRAW { Text("RAW").font(.caption.bold()) }
                    if app.pairing.isPaired(file.url) {
                        Label(L10n.hasPairing, systemImage: "link").font(.caption)
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
            .help(L10n.closeHelp)
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
            Button(L10n.fit) { resetZoom() }
                .buttonStyle(.plain)
                .disabled(zoom == 1)

            Spacer()
            Text(positionText).font(.callout)
            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showEXIF.toggle() }
            } label: {
                Image(systemName: showEXIF ? "info.circle.fill" : "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(showEXIF ? Color.accentColor : .white)
            .help(L10n.togglePhotoInfoHelp)

            Button {
                app.openEditor(file.url)
            } label: {
                Label(L10n.edit, systemImage: "slider.horizontal.3")
            }
            .keyboardShortcut("e", modifiers: [.command])

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(L10n.moveToTrash, systemImage: "trash")
            }
            .help(L10n.moveToTrashDeleteHelp)
        }
        .foregroundStyle(.white)
        .padding()
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }

    // MARK: - EXIF overlay

    private var exifOverlay: some View {
        VStack {
            Spacer()
            HStack {
                exifCard
                Spacer()
            }
        }
        .padding(.leading, 20)
        .padding(.bottom, 86)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    @ViewBuilder
    private var exifCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "camera.aperture")
                Text(L10n.photoInfo).font(.caption.bold())
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.bottom, 2)

            if let exif {
                if let dim = exif.dimensionDescription { exifRow(L10n.dimensions, dim) }
                if let model = exif.cameraModel { exifRow(L10n.camera, model) }
                if let lens = exif.lensModel { exifRow(L10n.lens, lens) }
                exifExposureRow
                if let fl = exif.focalLength { exifRow(L10n.focalLength, String(format: "%.0fmm", fl)) }
                if let date = exif.dateTaken { exifRow(L10n.captured, date) }
            } else {
                Text(L10n.loadingExif).font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            if let size = file.fileSize {
                exifRow(L10n.size, ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            }
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder
    private var exifExposureRow: some View {
        if let exif {
            let parts: [String] = [
                exif.iso.map { "ISO \($0)" },
                exif.aperture.map { String(format: "f/%.1f", $0) },
                exif.shutterSpeed.map { "\($0)s" }
            ].compactMap { $0 }
            if !parts.isEmpty {
                exifRow(L10n.exposure, parts.joined(separator: " · "))
            }
        }
    }

    private func exifRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(key).foregroundStyle(.white.opacity(0.55)).frame(width: 36, alignment: .leading)
            Text(value).foregroundStyle(.white.opacity(0.95)).lineLimit(2)
        }
        .font(.caption)
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

    /// The editor sits on top of the preview; when it's open the preview must not
    /// also bind the same keys (Esc / Delete / etc.).
    private var editorOnTop: Bool { app.editorURL != nil }

    private var closeShortcut: some View {
        Button("", action: app.closePreview)
            .keyboardShortcut(.cancelAction)
            .disabled(editorOnTop)
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
            Button("") { showEXIF.toggle() }.keyboardShortcut("i", modifiers: [])
            // Delete key (Backspace) + fn+Delete both trigger the delete confirm.
            Button("") { showDeleteConfirm = true }.keyboardShortcut(.delete, modifiers: [])
            Button("") { showDeleteConfirm = true }.keyboardShortcut(.deleteForward, modifiers: [])
        }
        .disabled(editorOnTop)
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}

#if canImport(AppKit)
/// Transparent NSView that forwards scroll-wheel delta to SwiftUI.
private struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            onScroll?(event.scrollingDeltaY)
        }
    }
}
#else
private struct ScrollWheelCatcher: View {
    var onScroll: (CGFloat) -> Void
    var body: some View { Color.clear }
}
#endif
