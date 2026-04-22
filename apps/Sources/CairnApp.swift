import SwiftUI

@main
struct CairnApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            WindowScene(app: app)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Placeholder for Settings Scene — actual UI lands in Phase 2/3.
    }
}

/// Per-window wrapper. Owns a `WindowSceneModel` scoped to this scene and
/// injects it + `AppModel` into the environment for ContentView and friends.
///
/// Extracted in M1.8 T10 so each window gets its own `[Tab]`. When multi-window
/// lands in T11 a second WindowGroup scene will create an independent
/// WindowSceneModel with its own tab list; AppModel (engine, bookmarks, etc.)
/// stays shared across all windows.
struct WindowScene: View {
    let app: AppModel
    @State private var scene: WindowSceneModel

    init(app: AppModel) {
        self.app = app
        _scene = State(initialValue: WindowSceneModel(
            engine: app.engine,
            bookmarks: app.bookmarks,
            initialURL: app.bootstrapInitialURL()
        ))
    }

    var body: some View {
        ContentView()
            .environment(app)
            .environment(scene)
            .environment(\.cairnTheme, .glass)
            .frame(minWidth: 800, minHeight: 500)
            .background(VisualEffectBlur(material: .sidebar).ignoresSafeArea())
    }
}
