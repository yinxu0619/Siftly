import SwiftUI

struct DeleteConfirmationView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var working = false
    @State private var showFinalConfirm = false
    @State private var permanent = false
    /// Built once when the sheet opens. As a computed property this ran ~7x per
    /// body evaluation, and the body re-evaluates on every deletion progress
    /// tick — hundreds of full plan builds (each with two sorts) during exactly
    /// the operation that should stay responsive. The selection can't change
    /// while this modal sheet is up, so one build is enough.
    @State private var plan = DeletionPlan(directlySelected: [], pairedAdditions: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n.confirmDelete, systemImage: "trash")
                .font(.title2.bold())

            Text(L10n.deletePlanBody(plan.count, plan.totalSizeDescription, permanent))
                .foregroundStyle(.secondary)

            if !permanent, app.selectedVolumeIsRemovable {
                Label(L10n.trashStaysOnCardHint, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            if app.crossCardMode {
                Label(L10n.crossCardWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            List {
                if !plan.directlySelected.isEmpty {
                    Section(L10n.directlySelected(plan.directlySelected.count)) {
                        ForEach(plan.directlySelected) { file in
                            fileRow(file, paired: false)
                        }
                    }
                }
                if !plan.pairedAdditions.isEmpty {
                    Section(L10n.pairedAdditions(plan.pairedAdditions.count)) {
                        ForEach(plan.pairedAdditions) { file in
                            fileRow(file, paired: true)
                        }
                    }
                }
            }
            .frame(minHeight: 240)

            Toggle(isOn: $permanent) {
                Label(L10n.deleteDirectToggle, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(permanent ? Color.red : Color.primary)
            }
            .toggleStyle(.checkbox)
            .disabled(working)

            if working {
                ProgressView(value: app.deletionProgress) {
                    Text(L10n.deletingProgress(app.deletionDone, app.deletionTotal, permanent))
                        .font(.caption)
                }
            }

            HStack {
                Spacer()
                Button(L10n.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button(permanent ? L10n.deletePermanent : L10n.moveToTrash, role: .destructive) {
                    showFinalConfirm = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
        }
        .padding()
        .frame(width: 460, height: 500)
        .task { plan = app.planDeletion() }
        .confirmationDialog(
            permanent ? L10n.confirmPermanentDialog(plan.count) : L10n.confirmTrashDialog(plan.count),
            isPresented: $showFinalConfirm,
            titleVisibility: .visible
        ) {
            Button(permanent ? L10n.deletePermanent : L10n.moveToTrash, role: .destructive) {
                let captured = plan
                let isPermanent = permanent
                working = true
                Task {
                    await app.performDeletion(captured, permanent: isPermanent)
                    working = false
                    dismiss()
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(permanent ? L10n.permanentDialogMessage : L10n.trashDialogMessage)
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
