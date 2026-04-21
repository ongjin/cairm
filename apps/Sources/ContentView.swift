import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @State private var folder: FolderModel?

    var body: some View {
        @Bindable var app = app
        return NavigationSplitView {
            SidebarView(app: app)
        } content: {
            if let folder {
                FileListView(
                    folder: folder,
                    onActivate: handleOpen,
                    onAddToPinned: handleAddToPinned,
                    isPinnedCheck: { entry in
                        app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
                    },
                    onSelectionChanged: handleSelectionChanged
                )
            } else {
                ProgressView().controlSize(.small)
            }
        } detail: {
            PreviewPaneView(preview: app.preview)
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
            ToolbarItem(placement: .principal) {
                BreadcrumbBar(app: app)
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { app.toggleCurrentFolderPin() }) {
                    Image(systemName: pinIconName)
                }
                .help(app.currentFolder.map(app.bookmarks.isPinned) == true ? "Unpin current folder" : "Pin current folder")
                .keyboardShortcut("d", modifiers: [.command])
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { toggleShowHidden() }) {
                    Image(systemName: app.showHidden ? "eye" : "eye.slash")
                }
                .help(app.showHidden ? "Hide hidden files" : "Show hidden files")
                .keyboardShortcut(".", modifiers: [.command, .shift])
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
            app.lastFolder.save(url)
            Task { await folder?.load(url) }
        }
    }

    private var pinIconName: String {
        guard let url = app.currentFolder else { return "pin" }
        return app.bookmarks.isPinned(url: url) ? "pin.fill" : "pin"
    }

    private func ensureFolderModel() {
        if folder == nil { folder = FolderModel(engine: app.engine) }
    }

    private func handleOpen(_ entry: FileEntry) {
        let url = URL(fileURLWithPath: entry.path.toString())
        if entry.kind == .Directory {
            app.history.push(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleAddToPinned(_ entry: FileEntry) {
        guard entry.kind == .Directory else { return }
        let url = URL(fileURLWithPath: entry.path.toString())
        try? app.bookmarks.togglePin(url: url)
    }

    private func handleSelectionChanged(_ entry: FileEntry?) {
        if let e = entry {
            app.preview.focus = URL(fileURLWithPath: e.path.toString())
        } else {
            app.preview.focus = nil
        }
    }

    private func toggleShowHidden() {
        app.toggleShowHidden()
        if let url = app.currentFolder {
            Task { await folder?.load(url) }
        }
    }
}
