import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var app: AppState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            VolumeSidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } content: {
            ThumbnailGridView()
                .navigationSplitViewColumnWidth(min: 420, ideal: 700)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        }
        .overlay {
            if let file = app.previewFile {
                PreviewView(file: file)
                    .environmentObject(app)
                    .transition(.opacity)
            }
        }
        .overlay {
            if let file = app.editorFile {
                EditorView(file: file)
                    .environmentObject(app)
                    .transition(.opacity)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { app.isShowingDeleteSheet },
                set: { app.isShowingDeleteSheet = $0 }
            )
        ) {
            DeleteConfirmationView()
                .environmentObject(app)
        }
        .sheet(
            isPresented: Binding(
                get: { app.isShowingAbout },
                set: { app.isShowingAbout = $0 }
            )
        ) {
            AboutView()
                .environmentObject(app)
        }
        .alert(
            L10n.errorTitle,
            isPresented: Binding(
                get: { app.errorMessage != nil },
                set: { if !$0 { app.errorMessage = nil } }
            )
        ) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}
