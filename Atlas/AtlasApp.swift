import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct AtlasApp: App {
    /// Named so the menu bar item can open a window when none exists. With a
    /// MenuBarExtra the app keeps running after its last window closes, and
    /// without an id there is no way to ask for a new one.
    static let mainWindowID = "atlas-main"
    static let sketchWindowID = "atlas-sketch"
    @StateObject private var model = AtlasAppModel()
    @StateObject private var appearance = AtlasAppearanceStore()

    var body: some Scene {
        WindowGroup(id: AtlasApp.mainWindowID) {
            RootView(model: model, appearance: appearance)
                .environment(\.atlasPalette, appearance.palette)
                .environment(\.atlasLogoStyle, appearance.logoStyle)
                .preferredColorScheme(appearance.effectiveColorScheme)
                .tint(appearance.palette.primary)
        }
        #if os(macOS)
        .defaultSize(width: 1_480, height: 960)
        // Without this a WindowGroup resizes itself to fit its content's ideal
        // height, so the window grows whenever the content does — which is how
        // it ended up 240 points taller than the display. contentMinSize keeps
        // a floor and nothing else: the window's size becomes the user's.
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
        }
        #endif

        #if os(macOS)
        Window("Sketch Pad", id: AtlasApp.sketchWindowID) {
            TrackpadSketchView(appModel: model)
                .environment(\.atlasPalette, appearance.palette)
                .environment(\.atlasLogoStyle, appearance.logoStyle)
                .preferredColorScheme(appearance.effectiveColorScheme)
                .tint(appearance.palette.primary)
        }
        .defaultSize(width: 1_180, height: 780)
        #endif

        // A lecture starts whether or not the window is open, so the record
        // control lives in the menu bar as well as in the app.
        #if os(macOS)
        MenuBarExtra {
            if let capture = model.lectureCapture {
                LectureMenuBarView(capture: capture)
                    .environment(\.atlasPalette, appearance.palette)
            } else {
                Text("Atlas is still opening.")
                    .padding()
            }
        } label: {
            Image(systemName: menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    #if os(macOS)
    private var menuBarSymbol: String {
        guard let capture = model.lectureCapture else { return "waveform" }
        if capture.isRecording { return "waveform.badge.mic" }
        if capture.phase.isBusy { return "waveform.badge.magnifyingglass" }
        return "waveform"
    }

    #endif
}
