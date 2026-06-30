import SwiftUI

/// Root SwiftUI application. Lives in the library (no `@main`) so the executable
/// host can boot it via `SiftlyApp.main()` and so it stays unit-testable.
public struct SiftlyApp: App {
    @StateObject private var app = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            // Route the standard "About Siftly" menu item to our own panel...
            CommandGroup(replacing: .appInfo) {
                Button(L10n.aboutSiftly) { app.isShowingAbout = true }
            }
            // ...and remove the default Help menu.
            CommandGroup(replacing: .help) {}
        }

        Settings {
            SettingsView()
                .environmentObject(app)
        }
    }
}
