import SwiftUI

struct ThumbnailGridView: View {
    @EnvironmentObject private var app: AppState
    @State private var thumbSize: CGFloat = 150

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbSize, maximum: thumbSize * 1.6), spacing: 10)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(app.displayedFiles) { file in
                    ThumbnailItemView(file: file, size: thumbSize)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if app.browseSelection != nil && !app.files.isEmpty {
                FilterBarView()
            }
        }
        .overlay {
            if app.isScanning {
                ProgressView("扫描中…")
            } else if app.browseSelection == nil {
                ContentUnavailableView("请选择左侧的存储卡", systemImage: "sidebar.left")
            } else if app.files.isEmpty {
                ContentUnavailableView("没有可显示的文件", systemImage: "photo.on.rectangle")
            } else if app.displayedFiles.isEmpty {
                ContentUnavailableView(
                    "无匹配的文件",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("调整或清除筛选条件")
                )
            }
        }
        .toolbar { toolbarContent }
        .navigationTitle(app.crossCardMode ? "所有存储卡" : (app.selectedVolume?.name ?? "Siftly"))
        .navigationSubtitle(app.statusMessage)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Text("已选 \(app.selection.count)")
                .foregroundStyle(.secondary)

            Button {
                app.selectAll()
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .help("全选")
            .keyboardShortcut("a", modifiers: [.command])
            .disabled(app.displayedFiles.isEmpty)

            Menu {
                Button("反选") { app.invertSelection() }
                Button("取消选择") { app.clearSelection() }
                Divider()
                Menu("批量评分") {
                    ForEach([5, 4, 3, 2, 1], id: \.self) { star in
                        Button(String(repeating: "★", count: star)) {
                            app.setRatingForSelection(Rating(rawValue: star)!)
                        }
                    }
                    Button("清除评分") { app.setRatingForSelection(.none) }
                }
                Menu("批量标签") {
                    ForEach(ColorLabel.allCases) { label in
                        Button(label.displayName) { app.setLabelForSelection(label) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("选择与批量标记")
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
            .help("配对规则（佳能 / 尼康 / 富士 / 索尼 / 通用）")

            Button(role: .destructive) {
                app.isShowingDeleteSheet = true
            } label: {
                Image(systemName: "trash")
            }
            .help("移入废纸篓（含配对文件）")
            .disabled(app.selection.isEmpty || app.isScanning || app.isDeleting)
            .keyboardShortcut(.delete, modifiers: [])

            Button {
                app.undoLastDeletion()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("撤销上次删除（从废纸篓恢复）")
            .disabled(!app.canUndo || app.isDeleting)
            .keyboardShortcut("z", modifiers: [.command])

            Slider(value: $thumbSize, in: 90...260) {
                Text("缩略图大小")
            }
            .frame(width: 120)
        }
    }
}
