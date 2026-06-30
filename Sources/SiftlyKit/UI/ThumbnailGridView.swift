import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ThumbnailGridView: View {
    @EnvironmentObject private var app: AppState
    @State private var thumbSize: CGFloat = 150

    // Marquee (rubber-band) selection state.
    @State private var itemFrames: [URL: CGRect] = [:]
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBase: Set<URL> = []
    private let gridSpace = "siftly.grid"

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbSize, maximum: thumbSize * 1.6), spacing: 10)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(app.displayedFiles) { file in
                    ThumbnailItemView(file: file, size: thumbSize)
                        .background(frameReporter(file.url))
                }
            }
            .padding()
            .background(marqueeLayer)
            .overlay(marqueeRectangle)
            .coordinateSpace(name: gridSpace)
            .onPreferenceChange(ItemFrameKey.self) { itemFrames = $0 }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if app.browseSelection != nil && !app.files.isEmpty {
                FilterBarView()
            }
        }
        .overlay {
            if app.isScanning {
                ProgressView(L10n.scanning)
            } else if app.browseSelection == nil {
                ContentUnavailableView(L10n.selectCardPrompt, systemImage: "sidebar.left")
            } else if app.files.isEmpty {
                ContentUnavailableView(L10n.noFilesToShow, systemImage: "photo.on.rectangle")
            } else if app.displayedFiles.isEmpty {
                ContentUnavailableView(
                    L10n.noMatchingFiles,
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text(L10n.adjustFiltersHint)
                )
            }
        }
        .background(hotkeys)
        .toolbar { toolbarContent }
        .navigationTitle(app.crossCardMode ? L10n.allStorageCards : (app.selectedVolume?.name ?? L10n.appName))
        .navigationSubtitle(app.statusMessage)
    }

    // MARK: - Marquee selection

    private func frameReporter(_ url: URL) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: ItemFrameKey.self, value: [url: geo.frame(in: .named(gridSpace))])
        }
    }

    private var marqueeRect: CGRect {
        guard let s = marqueeStart, let c = marqueeCurrent else { return .zero }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    /// Transparent layer behind the grid items; a drag starting on empty space
    /// draws a selection rectangle and selects intersecting thumbnails.
    private var marqueeLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(gridSpace))
                    .onChanged { value in
                        if marqueeStart == nil {
                            marqueeStart = value.startLocation
                            #if canImport(AppKit)
                            marqueeBase = NSEvent.modifierFlags.contains(.command) ? app.selection : []
                            #else
                            marqueeBase = []
                            #endif
                        }
                        marqueeCurrent = value.location
                        let rect = marqueeRect
                        let hits = Set(itemFrames.filter { $0.value.intersects(rect) }.map(\.key))
                        app.setMarqueeSelection(hits, base: marqueeBase)
                    }
                    .onEnded { _ in
                        marqueeStart = nil
                        marqueeCurrent = nil
                    }
            )
    }

    @ViewBuilder
    private var marqueeRectangle: some View {
        if marqueeStart != nil, marqueeCurrent != nil {
            let r = marqueeRect
            Rectangle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                .frame(width: r.width, height: r.height)
                .position(x: r.midX, y: r.midY)
                .allowsHitTesting(false)
        }
    }

    /// When a full-screen overlay is up, the grid yields its key shortcuts to it
    /// (otherwise two views bind the same key and SwiftUI fires neither).
    private var overlayOpen: Bool { app.previewURL != nil || app.editorURL != nil }

    /// Hidden buttons that register extra keyboard shortcuts for the grid.
    /// ⌘A / ⌘Z live on the toolbar buttons.
    private var hotkeys: some View {
        Group {
            Button("") { app.selectAll() }
                .keyboardShortcut("a", modifiers: [.control])
                .disabled(app.displayedFiles.isEmpty)
            Button("") { app.invertSelection() }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(app.displayedFiles.isEmpty)
            Button("") { app.clearSelection() }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(app.selection.isEmpty)
            // Delete on Mac keyboards sends Backspace (.delete); cover forward
            // delete (fn+Delete) and ⌘⌫ too so the key always works.
            Button("") { requestGridDelete() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(app.selection.isEmpty || app.isScanning || app.isDeleting)
            Button("") { requestGridDelete() }
                .keyboardShortcut(.deleteForward, modifiers: [])
                .disabled(app.selection.isEmpty || app.isScanning || app.isDeleting)
            Button("") { requestGridDelete() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(app.selection.isEmpty || app.isScanning || app.isDeleting)
        }
        .disabled(overlayOpen)
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func requestGridDelete() {
        guard !app.selection.isEmpty, !app.isScanning, !app.isDeleting else { return }
        app.isShowingDeleteSheet = true
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Text(L10n.selectedCount(app.selection.count))
                .foregroundStyle(.secondary)

            Button {
                app.selectAll()
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .help(L10n.selectAllHelp)
            .keyboardShortcut("a", modifiers: [.command])
            .disabled(app.displayedFiles.isEmpty)

            Menu {
                Button(L10n.invertSelection) { app.invertSelection() }
                Button(L10n.clearSelection) { app.clearSelection() }
                Divider()
                Menu(L10n.batchRating) {
                    ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                        Button(String(repeating: "★", count: star)) {
                            app.setRatingForSelection(Rating(rawValue: star)!)
                        }
                    }
                    Button(L10n.clearRating) { app.setRatingForSelection(.none) }
                }
                Menu(L10n.batchLabels) {
                    ForEach(ColorLabel.allCases) { label in
                        Button(label.displayName) { app.setLabelForSelection(label) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help(L10n.selectionAndBatchHelp)
            .disabled(app.selection.isEmpty)

            Menu {
                ForEach(PairingRule.presets, id: \.name) { rule in
                    Button {
                        app.applyPairingRule(rule)
                    } label: {
                        if app.pairingRule.name == rule.name {
                            Label(rule.name, systemImage: "checkmark")
                        } else {
                            Text(rule.name)
                        }
                    }
                }
            } label: {
                Image(systemName: "link")
            }
            .help(L10n.pairingRulesHelp)

            Button(role: .destructive) {
                requestGridDelete()
            } label: {
                Image(systemName: "trash")
            }
            .help(L10n.moveToTrashHelp)
            .disabled(app.selection.isEmpty || app.isScanning || app.isDeleting)

            Button {
                app.undoLastDeletion()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help(L10n.undoDeleteHelp)
            .disabled(!app.canUndo || app.isDeleting)
            .keyboardShortcut("z", modifiers: [.command])

            Slider(value: $thumbSize, in: 90...260) {
                Text(L10n.thumbnailSize)
            }
            .frame(width: 120)
        }
    }
}

/// Collects each thumbnail's frame (in the grid coordinate space) for marquee
/// hit-testing.
private struct ItemFrameKey: PreferenceKey {
    static var defaultValue: [URL: CGRect] = [:]
    static func reduce(value: inout [URL: CGRect], nextValue: () -> [URL: CGRect]) {
        value.merge(nextValue()) { _, b in b }
    }
}
