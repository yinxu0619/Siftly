import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Identity of a thumbnail load, used as the `.task(id:)` key.
struct ThumbnailRequest: Hashable {
    let url: URL
    let bucket: CGFloat
}

/// One grid cell.
///
/// Deliberately *not* an `@EnvironmentObject` observer: subscribing to `AppState`
/// would invalidate every visible cell on any state change at all — the scan's
/// per-batch `statusMessage` updates, deletion progress ticks, every frame of a
/// marquee drag. Instead the parent passes the handful of values a cell renders,
/// and `Equatable` lets SwiftUI skip cells whose inputs didn't move. `app` is
/// held as a plain reference for actions only.
struct ThumbnailItemView: View, Equatable {
    let app: AppState
    let file: MediaFile
    let size: CGFloat
    let isSelected: Bool
    let isPaired: Bool
    let mark: FileMark
    let showsVolume: Bool

    @State private var image: NSImage?

    static func == (lhs: ThumbnailItemView, rhs: ThumbnailItemView) -> Bool {
        lhs.app === rhs.app
            && lhs.file.url == rhs.file.url
            && lhs.file.name == rhs.file.name
            && lhs.file.volumeName == rhs.file.volumeName
            && lhs.size == rhs.size
            && lhs.isSelected == rhs.isSelected
            && lhs.isPaired == rhs.isPaired
            && lhs.mark == rhs.mark
            && lhs.showsVolume == rhs.showsVolume
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                badges
            }
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            }

            Text(file.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: size)

            if showsVolume, let volumeName = file.volumeName {
                Label(volumeName, systemImage: "sdcard")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: size)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            app.openPreview(file.url)
        }
        .onTapGesture(count: 1) {
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift) {
                app.selectRange(to: file.url, additive: flags.contains(.command))
            } else {
                app.toggleSelection(file.url, exclusive: !flags.contains(.command))
            }
        }
        .contextMenu { contextMenu }
        // Keyed on the *bucket*, not the raw slider value, so dragging the size
        // slider only re-decodes when it actually crosses a resolution step —
        // and, unlike keying on the URL alone, growing past a step does refresh
        // the image instead of leaving a stale low-res one on screen.
        .task(id: ThumbnailRequest(url: file.url, bucket: bucket)) {
            image = app.thumbnails.cachedImage(for: file.url, bucket: bucket)
                ?? app.thumbnails.anyCachedImage(for: file.url)
            if let loaded = await app.thumbnails.image(for: file.url, bucket: bucket) {
                image = loaded
            }
        }
    }

    private var bucket: CGFloat { ThumbnailProvider.bucket(forPoints: size) }

    @ViewBuilder
    private var contextMenu: some View {
        Button {
            app.openPreview(file.url)
        } label: {
            Label(L10n.openPreview, systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Button {
            app.openEditor(file.url)
        } label: {
            Label(L10n.editPhoto, systemImage: "slider.horizontal.3")
        }

        Button {
            app.revealInFinder(file.url)
        } label: {
            Label(L10n.revealInFinder, systemImage: "folder")
        }

        Button {
            app.openWithDefaultApp(file.url)
        } label: {
            Label(L10n.openWithDefaultApp, systemImage: "square.and.arrow.up")
        }

        Divider()

        Menu {
            ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                Button {
                    app.setRating(Rating(rawValue: star)!, for: file)
                } label: {
                    Label(String(repeating: "★", count: star), systemImage: "star")
                }
            }
            Button(L10n.clearRating) { app.setRating(.none, for: file) }
        } label: {
            Label(L10n.rating, systemImage: "star")
        }

        Menu {
            ForEach(ColorLabel.allCases) { label in
                Button {
                    app.setLabel(label, for: file)
                } label: {
                    Text(label.displayName)
                }
            }
        } label: {
            Label(L10n.label, systemImage: "tag")
        }

        Divider()

        Button {
            app.copyToClipboard(file.name)
        } label: {
            Label(L10n.copyFilename, systemImage: "doc.on.doc")
        }
        Button {
            app.copyToClipboard(file.url.path)
        } label: {
            Label(L10n.copyPath, systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            app.requestDelete(for: file.url)
        } label: {
            Label(L10n.moveToTrash, systemImage: "trash")
        }
    }

    private var badges: some View {
        VStack {
            HStack {
                if file.isRAW {
                    Text("RAW")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                }
                Spacer()
                if isPaired {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .bold))
                        .padding(4)
                        .background(.thinMaterial, in: Circle())
                }
            }
            Spacer()
            HStack {
                if mark.label != .none {
                    Circle().fill(mark.label.color).frame(width: 10, height: 10)
                }
                Spacer()
                if mark.rating != .none {
                    HStack(spacing: 1) {
                        ForEach(0..<mark.rating.stars, id: \.self) { _ in
                            Image(systemName: "star.fill").font(.system(size: 7))
                        }
                    }
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 3).padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                }
            }
        }
        .padding(5)
    }
}
