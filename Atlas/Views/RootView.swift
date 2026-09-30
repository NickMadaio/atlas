import AtlasCore
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AtlasAppModel
    @ObservedObject var appearance: AtlasAppearanceStore
    @ObservedObject private var auth: AuthSessionStore
    @State private var showsSettings: Bool

    init(model: AtlasAppModel, appearance: AtlasAppearanceStore) {
        self.model = model
        self.appearance = appearance
        auth = model.auth
#if DEBUG
        _showsSettings = State(initialValue: ProcessInfo.processInfo.arguments.contains("--atlas-open-appearance"))
#else
        _showsSettings = State(initialValue: false)
#endif
    }

    @ViewBuilder
    private func workspace(library: AtlasLibraryStore) -> some View {
        let view = WorkspaceView(
            library: library,
            auth: auth,
            environment: model.environment,
            showSettings: { showsSettings = true },
            reportError: model.report
        )
#if os(macOS)
        if let capture = model.lectureCapture {
            view.environmentObject(capture)
        } else {
            view
        }
#else
        view
#endif
    }

    var body: some View {
        Group {
            if let launchError = model.launchError {
                ContentUnavailableView(
                    "Atlas could not open",
                    systemImage: "exclamationmark.triangle",
                    description: Text(launchError)
                )
                .padding()
            } else if auth.state == .signedOut {
                LoginView(auth: auth, environment: model.environment, showAppearance: { showsSettings = true })
            } else if let library = model.library {
                workspace(library: library)
            } else {
                ProgressView("Opening Atlas…")
            }
        }
        .sheet(isPresented: $showsSettings) {
            AtlasSettingsView(settings: model.settings, appearance: appearance)
                .environment(\.atlasPalette, appearance.palette)
                .environment(\.atlasLogoStyle, appearance.logoStyle)
        }
#if os(macOS)
        // A restored frame can be bigger than the display it comes back on,
        // which puts the title bar above the top of the screen and cuts off the
        // foot of every layout.
        .atlasFitsItsWindow(minimumWidth: 1_260, minimumHeight: 760)
#endif
        .alert(
            "Atlas needs attention",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.presentedError = nil }
        } message: {
            Text(model.presentedError ?? "An unknown error occurred.")
        }
    }
}
