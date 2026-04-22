import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(WindowSceneModel.self) private var scene
    @Environment(\.cairnTheme) private var theme
    @FocusState private var searchFocused: Bool

    /// Current tab shorthand. Non-nil whenever the window has any tabs — which
    /// is the normal case. Early-access guards remain defensively because
    /// `closeTab` can momentarily leave `activeTab == nil` while the window
    /// tears down (T11).
    private var tab: Tab? { scene.activeTab }

    var body: some View {
        return NavigationSplitView {
            SidebarView(app: app, scene: scene)
        } content: {
            contentColumn
        } detail: {
            if let tab {
                PreviewPaneView(preview: tab.preview)
            } else {
                Color.clear
            }
        }
        .navigationTitle(tab?.currentFolder?.lastPathComponent ?? "Cairn")
        .toolbar { mainToolbar }
        .task {
            if let tab, let url = tab.currentFolder {
                await tab.folder.load(url)
            }
        }
        .onChange(of: tab?.currentFolder) { _, new in
            guard let tab else { return }
            guard let url = new else { tab.folder.clear(); return }
            app.lastFolder.save(url)
            Task { await tab.folder.load(url) }
            triggerSearchRefresh()
        }
        .onChange(of: scene.activeTabID) { _, _ in
            // Tab switch — reload the newly-active tab's folder so its
            // FolderModel reflects its own currentFolder. T10 accepts the full
            // reload; T12+ can optimize to reuse cached entries.
            guard let tab, let url = tab.currentFolder else { return }
            Task { await tab.folder.load(url) }
        }
        .onChange(of: tab?.search.query) { _, _ in triggerSearchRefresh() }
        .onChange(of: tab?.search.scope) { _, _ in triggerSearchRefresh() }
        .onChange(of: tab?.folder.sortDescriptor) { _, _ in triggerSearchRefresh() }
        .onChange(of: app.showHidden) { _, _ in triggerSearchRefresh() }
    }

    @ViewBuilder
    private var contentColumn: some View {
        if let tab {
            VStack(spacing: 0) {
                if tab.search.phase == .capped {
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
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                contentBody(tab: tab)
            }
            .animation(.easeInOut(duration: 0.2), value: tab.search.phase)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private func contentBody(tab: Tab) -> some View {
        let folder = tab.folder
        let searchModel = tab.search
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
                app.reopenFolder(startingAt: tab.currentFolder) { url in
                    if tab.currentFolder == url {
                        Task { await folder.load(url) }
                    } else {
                        tab.navigate(to: url)
                    }
                }
            }
        } else {
            fileList(tab: tab)
        }
    }

    private func fileList(tab: Tab) -> some View {
        let folder = tab.folder
        let searchModel = tab.search
        let isActive = searchModel.isActive
        let entries: [FileEntry] = isActive ? searchModel.results : folder.sortedEntries
        let showFolderCol = isActive && searchModel.scope == .subtree
        let searchRoot: URL? = isActive ? tab.currentFolder : nil
        return FileListView(
            entries: entries,
            folder: folder,
            folderColumnVisible: showFolderCol,
            searchRoot: searchRoot,
            onActivate: { handleOpen($0, tab: tab) },
            onAddToPinned: handleAddToPinned,
            isPinnedCheck: { entry in
                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
            },
            onSelectionChanged: { handleSelectionChanged($0, tab: tab) }
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
            Button(action: { _ = tab?.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!(tab?.history.canGoBack ?? false))
            .keyboardShortcut(.leftArrow, modifiers: [.command])
        }
        ToolbarItem(placement: .navigation) {
            Button(action: { _ = tab?.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!(tab?.history.canGoForward ?? false))
            .keyboardShortcut(.rightArrow, modifiers: [.command])
        }
        ToolbarItem(placement: .navigation) {
            Button(action: { tab?.goUp() }) {
                Image(systemName: "arrow.up")
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])
        }
        ToolbarItem(placement: .principal) {
            BreadcrumbBar(tab: tab)
        }
        ToolbarItem(placement: .automatic) {
            Button(action: { tab?.toggleCurrentFolderPin() }) {
                Image(systemName: pinIconName)
            }
            .help(tab?.currentFolder.map(app.bookmarks.isPinned) == true ? "Unpin current folder" : "Pin current folder")
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
            .disabled(tab?.currentFolder == nil)
        }
        ToolbarItem(placement: .automatic) {
            if let tab {
                ThemedSearchField(search: tab.search, focused: $searchFocused)
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
        guard let url = tab?.currentFolder else { return "pin" }
        return app.bookmarks.isPinned(url: url) ? "pin.fill" : "pin"
    }

    private func handleOpen(_ entry: FileEntry, tab: Tab) {
        let url = URL(fileURLWithPath: entry.path.toString())
        if entry.kind == .Directory {
            tab.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func handleAddToPinned(_ entry: FileEntry) {
        guard entry.kind == .Directory else { return }
        let url = URL(fileURLWithPath: entry.path.toString())
        try? app.bookmarks.togglePin(url: url)
    }

    private func handleSelectionChanged(_ entry: FileEntry?, tab: Tab) {
        if let e = entry {
            tab.preview.focus = URL(fileURLWithPath: e.path.toString())
        } else {
            tab.preview.focus = nil
        }
    }

    private func toggleShowHidden() {
        app.toggleShowHidden()
        if let tab, let url = tab.currentFolder {
            Task { await tab.folder.load(url) }
        }
    }

    private func reloadCurrentFolder() {
        guard let tab, let url = tab.currentFolder else { return }
        Task { await tab.folder.load(url) }
    }

    private func triggerSearchRefresh() {
        guard let tab else { return }
        tab.search.refresh(
            root: tab.currentFolder,
            showHidden: app.showHidden,
            sort: tab.folder.sortDescriptor,
            folderEntries: tab.folder.sortedEntries
        )
    }
}
