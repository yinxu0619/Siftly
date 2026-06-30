import SwiftUI

/// App preferences (opened via the standard ⌘, / Siftly → Settings menu item).
struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section {
                Stepper(value: $app.previewPrefetchCount, in: 0...20) {
                    HStack {
                        Text(L10n.prefetchNeighbors)
                        Spacer()
                        Text(app.previewPrefetchCount == 0
                             ? L10n.prefetchOff
                             : L10n.prefetchPerSide(app.previewPrefetchCount))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(prefetchHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.prefetchSection)
            } footer: {
                Text(L10n.prefetchFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 240)
    }

    private var prefetchHint: String {
        switch app.previewPrefetchCount {
        case 0: return L10n.prefetchHintOff
        default:
            let total = app.previewPrefetchCount * 2
            return L10n.prefetchHintOn(total, total * 18)
        }
    }
}
