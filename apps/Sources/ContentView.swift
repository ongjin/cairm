import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var folder: FolderModel?

    var body: some View {
        @Bindable var app = app
        return Group {
            if app.currentFolder == nil {
                OpenFolderEmptyState(app: app)
            } else if let folder {
                NavigationSplitView {
                    sidebarPlaceholder
                } content: {
                    FileListSimpleView(folder: folder, onOpen: handleOpen)
                } detail: {
                    previewPlaceholder
                }
                .navigationTitle(app.currentFolder?.lastPathComponent ?? "Cairn")
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button(action: { app.goBack() }) {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!app.history.canGoBack)
                        .keyboardShortcut(.leftArrow, modifiers: [.command])
                    }
                    ToolbarItem(placement: .navigation) {
                        Button(action: { app.goForward() }) {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!app.history.canGoForward)
                        .keyboardShortcut(.rightArrow, modifiers: [.command])
                    }
                    ToolbarItem(placement: .navigation) {
                        Button(action: { app.goUp() }) {
                            Image(systemName: "arrow.up")
                        }
                        .keyboardShortcut(.upArrow, modifiers: [.command])
                    }
                }
            }
        }
        .task {
            ensureFolderModel()
            if let url = app.currentFolder {
                await folder?.load(url)
            }
        }
        .onChange(of: app.currentFolder) { _, new in
            ensureFolderModel()
            guard let url = new else { folder?.clear(); return }
            Task { await folder?.load(url) }
        }
    }

    private func ensureFolderModel() {
        if folder == nil { folder = FolderModel(engine: app.engine) }
    }

    private func handleOpen(_ entry: FileEntry) {
        // `.Directory` is swift-bridge's default casing (Rust variant preserved).
        if entry.kind == .Directory {
            // Navigate into a subfolder of the current root — access already granted.
            let url = URL(fileURLWithPath: entry.path.toString())
            app.history.push(url)
        } else {
            // File open: delegate to Finder for now (Phase 2 adds in-app preview / default-app resolution).
            NSWorkspace.shared.open(URL(fileURLWithPath: entry.path.toString()))
        }
    }

    private var sidebarPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SIDEBAR").font(.caption).foregroundStyle(.secondary)
            Text("Pinned / Recent / Devices — M1.3")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(12)
        .frame(minWidth: 180)
    }

    private var previewPlaceholder: some View {
        VStack {
            Text("PREVIEW")
                .font(.caption).foregroundStyle(.secondary)
            Text("M1.4").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
