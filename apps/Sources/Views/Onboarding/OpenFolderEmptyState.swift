import SwiftUI
import AppKit

/// Shown when AppModel has no currentFolder — user needs to pick a starting point
/// via NSOpenPanel, since App Sandbox requires explicit folder consent.
struct OpenFolderEmptyState: View {
    @Bindable var app: AppModel
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("🏔️")
                .font(.system(size: 72))

            VStack(spacing: 6) {
                Text("Open a folder to get started")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text("Cairn runs in the App Sandbox, so you need to pick a folder once. We'll remember it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button(action: presentOpenPanel) {
                Label("Choose Folder…", systemImage: "folder")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("o", modifiers: [.command])

            if let msg = errorMessage {
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try app.openAndNavigate(to: url)
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't register folder: \(error.localizedDescription)"
            }
        }
    }
}
