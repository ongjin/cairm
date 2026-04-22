import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.cairnTheme) private var theme
    @State private var folder: FolderModel?
    @State private var searchModel: SearchModel?
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var app = app
        return NavigationSplitView {
            SidebarView(app: app)
        } content: {
            contentColumn
        } detail: {
            PreviewPaneView(preview: app.preview)
        }
        .navigationTitle(app.currentFolder?.lastPathComponent ?? "Cairn")
        .toolbar { mainToolbar }
        .task {
            ensureFolderModel()
            ensureSearchModel()
            if let url = app.currentFolder {
                await folder?.load(url)
            }
        }
        .onChange(of: app.currentFolder) { _, new in
            ensureFolderModel()
            guard let url = new else { folder?.clear(); return }
            app.lastFolder.save(url)
            Task { await folder?.load(url) }
            triggerSearchRefresh()
        }
        .onChange(of: searchModel?.query) { _, _ in triggerSearchRefresh() }
        .onChange(of: searchModel?.scope) { _, _ in triggerSearchRefresh() }
        .onChange(of: folder?.sortDescriptor) { _, _ in triggerSearchRefresh() }
        .onChange(of: app.showHidden) { _, _ in triggerSearchRefresh() }
    }

    @ViewBuilder
    private var contentColumn: some View {
        if let folder, let searchModel {
            VStack(spacing: 0) {
                if searchModel.phase == .capped {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Showing first 5,000 results — refine your query")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                }

                contentBody(folder: folder, searchModel: searchModel)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private func contentBody(folder: FolderModel, searchModel: SearchModel) -> some View {
        if searchModel.isActive
            && searchModel.results.isEmpty
            && searchModel.phase != .running
        {
            EmptyStateView.searchNoMatch(query: searchModel.query)
        } else if !searchModel.isActive
            && folder.state == .loaded
            && folder.entries.isEmpty
        {
            EmptyStateView.emptyFolder()
        } else if case .failed(let msg) = folder.state, !searchModel.isActive {
            EmptyStateView.permissionDenied(message: msg) {
                app.reopenCurrentFolder { url in
                    if app.currentFolder == url {
                        Task { await folder.load(url) }
                    } else {
                        app.history.push(url)
                    }
                }
            }
        } else {
            fileList(folder: folder, searchModel: searchModel)
        }
    }

    private func fileList(folder: FolderModel, searchModel: SearchModel) -> some View {
        let isActive = searchModel.isActive
        let entries: [FileEntry] = isActive ? searchModel.results : folder.sortedEntries
        let showFolderCol = isActive && searchModel.scope == .subtree
        let searchRoot: URL? = isActive ? app.currentFolder : nil
        return FileListView(
            entries: entries,
            folder: folder,
            folderColumnVisible: showFolderCol,
            searchRoot: searchRoot,
            onActivate: handleOpen,
            onAddToPinned: handleAddToPinned,
            isPinnedCheck: { entry in
                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
            },
            onSelectionChanged: handleSelectionChanged
        )
        .background {
            ZStack {
                VisualEffectBlur(material: .contentBackground)
                theme.panelTint.opacity(0.55)
            }
            .ignoresSafeArea()
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
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
        ToolbarItem(placement: .automatic) {
            Button(action: { reloadCurrentFolder() }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload")
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(app.currentFolder == nil)
        }
        ToolbarItem(placement: .automatic) {
            if let searchModel {
                ThemedSearchField(search: searchModel, focused: $searchFocused)
            }
        }
        ToolbarItem(placement: .automatic) {
            // Hidden button to expose the ⌘F shortcut at the app level.
            Button(action: { searchFocused = true }) { EmptyView() }
                .keyboardShortcut("f", modifiers: [.command])
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }

    private var pinIconName: String {
        guard let url = app.currentFolder else { return "pin" }
        return app.bookmarks.isPinned(url: url) ? "pin.fill" : "pin"
    }

    private func ensureFolderModel() {
        if folder == nil { folder = FolderModel(engine: app.engine) }
    }

    private func ensureSearchModel() {
        if searchModel == nil { searchModel = SearchModel(engine: app.engine) }
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

    private func reloadCurrentFolder() {
        guard let url = app.currentFolder else { return }
        Task { await folder?.load(url) }
    }

    private func triggerSearchRefresh() {
        guard let searchModel, let folder else { return }
        searchModel.refresh(
            root: app.currentFolder,
            showHidden: app.showHidden,
            sort: folder.sortDescriptor,
            folderEntries: folder.sortedEntries
        )
    }
}
