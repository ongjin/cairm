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

    @State private var palette = CommandPaletteModel()
    @State private var detailVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabBarView(scene: scene)
                NavigationSplitView(columnVisibility: $detailVisibility) {
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
                .onChange(of: app.showHidden) { _, _ in
                    if let tab, let url = tab.currentFolder {
                        Task { await tab.folder.load(url) }
                    }
                    triggerSearchRefresh()
                }
            }

            if palette.isOpen, let tab {
                CommandPaletteView(
                    model: palette,
                    tab: tab,
                    commands: builtinCommands(),
                    onActivate: handlePaletteActivate
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: palette.isOpen)
        .focusedSceneValue(\.paletteModel, palette)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            guard palette.isOpen else { return }
            if case .content = CommandPaletteModel.parse(palette.query) {
                palette.pollContent()
            }
        }
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
            folderRoot: tab.currentFolder,
            gitSnapshot: tab.git?.snapshot,
            onActivate: { handleOpen($0, tab: tab) },
            onAddToPinned: handleAddToPinned,
            isPinnedCheck: { entry in
                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
            },
            onSelectionChanged: { handleSelectionChanged($0, tab: tab) }
        )
        .background {
            ZStack {
                VisualEffectBlur(material: .headerView)
                LinearGradient(
                    colors: [
                        theme.panelTint.opacity(0.18),
                        theme.panelTint.opacity(0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
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
            Button(action: {
                detailVisibility = (detailVisibility == .all) ? .doubleColumn : .all
            }) {
                Image(systemName: detailVisibility == .all
                      ? "sidebar.right"
                      : "sidebar.squares.right")
            }
            .help("Toggle Preview Pane")
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }

    private func builtinCommands() -> [PaletteCommand] {
        guard let tab else { return [] }
        return [
            PaletteCommand(id: "newTab", label: "New Tab", iconSF: "plus.square", shortcutHint: "⌘T") { scene.newTab() },
            PaletteCommand(id: "closeTab", label: "Close Tab", iconSF: "xmark.square", shortcutHint: "⌘W") {
                if let id = scene.activeTabID { scene.closeTab(id) }
            },
            PaletteCommand(id: "reload", label: "Reload", iconSF: "arrow.clockwise", shortcutHint: "⌘R") {
                if let u = tab.currentFolder { Task { await tab.folder.load(u) } }
            },
            PaletteCommand(id: "toggleHidden", label: "Toggle Hidden Files", iconSF: "eye", shortcutHint: "⌘⇧.") {
                app.toggleShowHidden()
            },
            PaletteCommand(id: "pinFolder", label: "Pin Current Folder", iconSF: "pin", shortcutHint: "⌘D") {
                tab.toggleCurrentFolderPin()
            },
            PaletteCommand(id: "goUp", label: "Go to Parent Folder", iconSF: "arrow.up", shortcutHint: "⌘↑") {
                tab.goUp()
            },
        ]
    }

    private func handlePaletteActivate(_ data: PaletteRowData) {
        switch data {
        case .file(let f):
            if let tab {
                let url = tab.currentFolder?.appendingPathComponent(f.pathRel) ?? URL(fileURLWithPath: f.pathRel)
                openURL(url, tab: tab)
            }
        case .command(let c):
            c.run()
        case .content(let h):
            if let tab {
                let url = tab.currentFolder?.appendingPathComponent(h.pathRel) ?? URL(fileURLWithPath: h.pathRel)
                openURL(url, tab: tab)
            }
        case .symbol(let s):
            if let tab {
                let url = tab.currentFolder?.appendingPathComponent(s.pathRel) ?? URL(fileURLWithPath: s.pathRel)
                openURL(url, tab: tab)
            }
        }
        palette.close()
    }

    private func openURL(_ url: URL, tab: Tab) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            tab.navigate(to: url)
        } else {
            NSWorkspace.shared.open(url)
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
