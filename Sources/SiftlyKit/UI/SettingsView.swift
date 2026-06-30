import SwiftUI

/// App preferences (opened via the standard ⌘, / Siftly → Settings menu item).
struct SettingsView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Form {
            Section {
                Picker(L10n.language, selection: languageBinding) {
                    Text(L10n.languageSystem).tag("system")
                    ForEach(AppState.supportedLanguages, id: \.self) { code in
                        Text(Self.languageName(code)).tag(code)
                    }
                }
                Text(L10n.languageRestartHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.languageSection)
            }

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
        .frame(width: 460, height: 320)
    }

    private var languageBinding: Binding<String> {
        Binding(
            get: { app.languageOverride ?? "system" },
            set: { app.languageOverride = ($0 == "system") ? nil : $0 }
        )
    }

    /// Native display name for a locale code (e.g. "English", "简体中文").
    private static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.capitalized
            ?? code
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
