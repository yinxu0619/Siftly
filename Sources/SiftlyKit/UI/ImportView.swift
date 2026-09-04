import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Copies files from the card to the computer, with optional verification and
/// an optional cleanup of the originals afterwards.
struct ImportView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    /// Import only the current selection (vs everything shown).
    let selectionOnly: Bool

    @State private var plan = ImportPlan()
    @State private var freeSpace: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L10n.importTitle, systemImage: "square.and.arrow.down.on.square")
                .font(.title2.bold())

            destinationRow
            Divider()
            options
            Divider()
            summary

            if app.isImporting { progress }

            Spacer(minLength: 0)
            buttons
        }
        .padding()
        .frame(width: 520, height: 520)
        .task(id: recomputeKey) { await recompute() }
    }

    /// Any input that changes what would be copied.
    private var recomputeKey: String {
        let destination = app.importSettings.destination?.path ?? ""
        return "\(destination)|\(app.importSettings.organization.rawValue)|\(app.importSettings.includesPairedFiles)"
    }

    // MARK: - Destination

    private var destinationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.importDestination).font(.subheadline.bold())
            HStack {
                Group {
                    if let destination = app.importSettings.destination {
                        Text(destination.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                    } else {
                        Text(L10n.importNoDestination).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                Spacer()
                if let freeSpace {
                    Text(L10n.importFreeSpace(
                        ByteCountFormatter.string(fromByteCount: freeSpace, countStyle: .file)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Button(L10n.importChooseFolder) { chooseDestination() }
                    .disabled(app.isImporting)
            }
        }
    }

    private func chooseDestination() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.importChooseFolder
        panel.directoryURL = app.importSettings.destination
        if panel.runModal() == .OK, let url = panel.url {
            app.importSettings.destination = url
        }
        #endif
    }

    // MARK: - Options

    private var options: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Picker(L10n.importOrganize, selection: $app.importSettings.organization) {
                    ForEach(ImportOrganization.allCases) { Text($0.title).tag($0) }
                }
                Text(app.importSettings.organization.example)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            toggle(
                L10n.importIncludePaired, L10n.importIncludePairedHelp,
                isOn: $app.importSettings.includesPairedFiles
            )
            toggle(
                L10n.importVerify, L10n.importVerifyHelp,
                isOn: $app.importSettings.verifies
            )
            toggle(
                L10n.importDeleteAfter, L10n.importDeleteAfterHelp,
                isOn: $app.importSettings.deletesAfterImport,
                destructive: true
            )
        }
        .disabled(app.isImporting)
    }

    private func toggle(
        _ title: String,
        _ help: String,
        isOn: Binding<Bool>,
        destructive: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
                .foregroundStyle(destructive && isOn.wrappedValue ? Color.red : Color.primary)
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Summary / progress

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.importSummary(plan.count, plan.totalSizeDescription))
                .font(.callout.bold())
            if !plan.skipped.isEmpty {
                Text(L10n.importSkipped(plan.skipped.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let freeSpace, plan.totalBytes > freeSpace {
                Label(
                    ImportError.notEnoughSpace(needed: plan.totalBytes, available: freeSpace)
                        .localizedDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: app.importProgress)
            HStack {
                Text(app.importCurrentName).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("\(app.importedCount) / \(app.importTotalCount)").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            if app.isImporting {
                Button(L10n.importCancel, role: .destructive) { app.cancelImport() }
            } else {
                Button(L10n.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.importStart) {
                    Task {
                        await app.performImport(plan)
                        await recompute()
                        if app.importFailures.isEmpty { dismiss() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(plan.isEmpty || app.importSettings.destination == nil)
            }
        }
    }

    private func recompute() async {
        plan = await app.planImport(selectionOnly: selectionOnly)
        freeSpace = app.importSettings.destination.flatMap(FileCopier.availableCapacity(at:))
    }
}
