import SwiftUI

struct ContentView: View {
    // M1.1 workspace — full UI lands in Tasks 10–12.
    @State private var status = "Engine not invoked yet."

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.teal.opacity(0.3), .indigo.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("🏔️")
                    .font(.system(size: 48))
                Text(status)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.white)
                Text("M1.1 — scaffolding")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            let engine = CairnEngine()
            do {
                let home = FileManager.default.homeDirectoryForCurrentUser
                let entries = try await engine.listDirectory(home)
                status = "Home has \(entries.count) entries (sandboxed — likely 0 until folder is opened)"
            } catch {
                status = "Engine call failed: \(error)"
            }
        }
    }
}
