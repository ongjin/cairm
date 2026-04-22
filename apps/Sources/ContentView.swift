import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(WindowSceneModel.self) private var scene
    @Environment(\.cairnTheme) private var theme

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
                theme.panelTint  // opacity 0.25 already baked into the token
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
        ToolbarItem(placement: .navigation) {
            BreadcrumbBar(tab: tab)
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: { /* T15: palette.open() */ }) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                    Text("⌘K")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .help("Open Command Palette (wired in T15)")
        }
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
