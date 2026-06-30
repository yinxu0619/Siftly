import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ThumbnailItemView: View {
    @EnvironmentObject private var app: AppState
    let file: MediaFile
    let size: CGFloat

    @State private var image: NSImage?

    private var isSelected: Bool { app.selection.contains(file.url) }
    private var isPaired: Bool { app.pairing.isPaired(file.url) }
    private var mark: FileMark { app.mark(for: file) }

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

            if app.crossCardMode, let volumeName = file.volumeName {
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
        .task(id: file.url) {
            image = await app.thumbnails.image(
                for: file.url,
                size: CGSize(width: size * 2, height: size * 2)
            )
        }
    }

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
