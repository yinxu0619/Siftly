import SwiftUI

/// Search / filter / sort bar shown above the thumbnail grid.
struct FilterBarView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 10) {
            searchField

            Picker("", selection: $app.formatFilter) {
                ForEach(FormatFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .labelsHidden()

            ratingMenu
            labelMenu
            sortMenu

            if app.hasActiveFilter {
                Button {
                    app.clearFilters()
                } label: {
                    Label("清除筛选", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }

            Spacer()

            Text("\(app.displayedFiles.count) / \(app.files.count)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索文件名", text: $app.searchText)
                .textFieldStyle(.plain)
                .frame(width: 150)
            if !app.searchText.isEmpty {
                Button {
                    app.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var ratingMenu: some View {
        Menu {
            Button("全部") { app.minRating = 0 }
            ForEach([1, 2, 3, 4, 5], id: \.self) { star in
                Button("\(String(repeating: "★", count: star)) 及以上") { app.minRating = star }
            }
        } label: {
            Label(app.minRating > 0 ? "★\(app.minRating)+" : "评分", systemImage: "star")
        }
        .fixedSize()
    }

    private var labelMenu: some View {
        Menu {
            Button("全部") { app.labelFilter = nil }
            ForEach(ColorLabel.allCases) { label in
                Button(label.displayName) { app.labelFilter = label }
            }
        } label: {
            Label(app.labelFilter.map { "标签:\($0.displayName)" } ?? "标签", systemImage: "tag")
        }
        .fixedSize()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortKey.allCases) { key in
                Button {
                    app.sortKey = key
                } label: {
                    if app.sortKey == key {
                        Label(key.title, systemImage: "checkmark")
                    } else {
                        Text(key.title)
                    }
                }
            }
            Divider()
            Toggle("升序", isOn: $app.sortAscending)
        } label: {
            Label("排序", systemImage: app.sortAscending ? "arrow.up" : "arrow.down")
        }
        .fixedSize()
    }
}
