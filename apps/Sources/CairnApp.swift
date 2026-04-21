import SwiftUI

@main
struct CairnApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .environment(\.cairnTheme, .glass)
                .frame(minWidth: 800, minHeight: 500)
                .background(VisualEffectBlur(material: .hudWindow).ignoresSafeArea())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        // Placeholder for Settings Scene — actual UI lands in Phase 2/3.
    }
}
