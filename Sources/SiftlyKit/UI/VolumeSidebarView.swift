import SwiftUI

struct VolumeSidebarView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        List(selection: selectionBinding) {
            if app.volumes.count > 1 {
                Section {
                    Label("所有存储卡", systemImage: "square.stack.3d.up")
                        .tag(AppState.allCardsTag)
                        .help("合并浏览所有卡，按文件名跨卡配对、同步删除")
                } header: {
                    Text("跨卡配对")
                }
            }

            Section("存储卡") {
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
                    "未检测到存储卡",
                    systemImage: "sdcard",
                    description: Text("插入 SD / CFexpress 卡后点击刷新")
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
                .help("刷新存储卡与文件列表")
            }
        }
        .navigationTitle("Siftly")
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
