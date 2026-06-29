import SwiftUI

struct DeleteConfirmationView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var showFinalConfirm = false
    @State private var permanent = false

    private var plan: DeletionPlan { app.planDeletion() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("确认删除", systemImage: "trash")
                .font(.title2.bold())

            Text("以下 \(plan.count) 个文件将\(permanent ? "被永久删除" : "被移入废纸篓")（共 \(plan.totalSizeDescription)）。配对文件会一并删除。")
                .foregroundStyle(.secondary)

            if app.crossCardMode {
                Label(
                    "跨卡模式：按文件名跨卡配对。请确认下方清单中各卡的文件确实对应同一张照片（相机文件名可能重复）。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            List {
                if !plan.directlySelected.isEmpty {
                    Section("已选择 (\(plan.directlySelected.count))") {
                        ForEach(plan.directlySelected) { file in
                            fileRow(file, paired: false)
                        }
                    }
                }
                if !plan.pairedAdditions.isEmpty {
                    Section("配对联动 (\(plan.pairedAdditions.count))") {
                        ForEach(plan.pairedAdditions) { file in
                            fileRow(file, paired: true)
                        }
                    }
                }
            }
            .frame(minHeight: 240)

            Toggle(isOn: $permanent) {
                Label("直接删除（不进废纸篓，不可恢复）", systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(permanent ? Color.red : Color.primary)
            }
            .toggleStyle(.checkbox)
            .disabled(working)

            if working {
                ProgressView(value: app.deletionProgress) {
                    Text("正在\(permanent ? "删除" : "移入废纸篓") \(app.deletionDone)/\(app.deletionTotal)")
                        .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button(permanent ? "直接删除" : "移入废纸篓", role: .destructive) {
                    showFinalConfirm = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
        }
        .padding()
        .frame(width: 460, height: 500)
        .confirmationDialog(
            permanent
                ? "确定永久删除 \(plan.count) 个文件？此操作不可恢复！"
                : "确定将 \(plan.count) 个文件移入废纸篓？",
            isPresented: $showFinalConfirm,
            titleVisibility: .visible
        ) {
            Button(permanent ? "永久删除" : "移入废纸篓", role: .destructive) {
                let captured = plan
                let isPermanent = permanent
                working = true
                Task {
                    await app.performDeletion(captured, permanent: isPermanent)
                    working = false
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(permanent
                ? "文件将从存储卡直接删除，无法通过废纸篓或撤销 (⌘Z) 恢复。"
                : "文件将移动到「废纸篓」，可在废纸篓或用撤销 (⌘Z) 恢复。")
        }
    }

    private func fileRow(_ file: MediaFile, paired: Bool) -> some View {
        HStack {
            Image(systemName: paired ? "link" : "doc")
                .foregroundStyle(paired ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name).lineLimit(1).truncationMode(.middle)
                if app.crossCardMode, let volumeName = file.volumeName {
                    Text(volumeName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let size = file.fileSize {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
