import SwiftUI

struct VolumeSidebarView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List(selection: selectionBinding) {
            if app.volumes.count > 1 {
                Section {
                    Label(L10n.allStorageCards, systemImage: "square.stack.3d.up")
                        .tag(AppState.allCardsTag)
                        .help(L10n.allStorageCardsHelp)
                } header: {
                    Text(L10n.crossCardPairing)
                }
            }

            Section(L10n.storageCards) {
                ForEach(app.volumes) { volume in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(volume.name, systemImage: "sdcard")
                        if !volume.capacityDescription.isEmpty {
                            Text(volume.capacityDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(volume.id)
                }
            }
        }
        .overlay {
            if app.volumes.isEmpty {
                ContentUnavailableView(
                    L10n.noStorageCards,
                    systemImage: "sdcard",
                    description: Text(L10n.insertCardHint)
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    app.manualRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(L10n.refreshHelp)
            }
        }
        .navigationTitle(L10n.appName)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { app.browseSelection },
            set: { newValue in
                if newValue == AppState.allCardsTag {
                    app.selectAllCards()
                } else if let id = newValue, let volume = app.volumes.first(where: { $0.id == id }) {
                    app.selectVolume(volume)
                }
            }
        )
    }
}
