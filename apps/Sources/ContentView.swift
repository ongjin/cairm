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
    @State private var showInspector: Bool = true
    /// Opaque token returned by `NSEvent.addLocalMonitorForEvents`. Held so we
    /// can remove the monitor on view teardown; losing it would leak the
    /// closure and keep dispatching events to a dead view.
    @State private var mouseNavMonitor: Any?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabBarView(scene: scene)
                NavigationSplitView {
                    SidebarView(app: app, scene: scene)
                } detail: {
                    contentColumn
                }
                .inspector(isPresented: $showInspector) {
                    if let tab {
                        PreviewPaneView(preview: tab.preview)
                    } else {
                        Color.clear
                    }
                }
                .navigationTitle({
                    guard let tab, let path = tab.currentPath else { return "Cairn" }
                    if case .ssh(let target) = path.provider {
                        let name = path.lastComponent.isEmpty ? "/" : path.lastComponent
                        return "\(target.hostname) · \(name)"
                    }
                    return tab.currentFolder?.lastPathComponent ?? "Cairn"
                }())
                .toolbar { mainToolbar }
                .task {
                    if let tab, let path = tab.currentPath {
                        await tab.folder.load(path, via: tab.provider)
                    }
                }
                .onChange(of: tab?.currentPath) { _, new in
                    guard let tab else { return }
                    guard let path = new else { tab.folder.clear(); return }
                    if case .local = path.provider {
                        app.lastFolder.save(URL(fileURLWithPath: path.path))
                    }
                    Task { await tab.folder.load(path, via: tab.provider) }
                    triggerSearchRefresh()
                }
                .onChange(of: scene.activeTabID) { _, _ in
                    // Tab switch — reload the newly-active tab's folder so its
                    // FolderModel reflects its own currentPath. T10 accepts the full
                    // reload; T12+ can optimize to reuse cached entries.
                    guard let tab, let path = tab.currentPath else { return }
                    Task { await tab.folder.load(path, via: tab.provider) }
                }
                .onChange(of: tab?.search.query) { _, _ in triggerSearchRefresh() }
                .onChange(of: tab?.search.scope) { _, _ in triggerSearchRefresh() }
                .onChange(of: tab?.folder.sortDescriptor) { _, _ in triggerSearchRefresh() }
                .onChange(of: app.showHidden) { _, _ in
                    if let tab, let path = tab.currentPath {
                        Task { await tab.folder.load(path, via: tab.provider) }
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
            if palette.mode == .content {
                palette.pollContent()
            }
        }
        .sheet(item: Bindable(scene).connectSheetModel) { model in
            ConnectSheetView(
                model: model,
                onConnect: { Task { await performConnect(model: model) } },
                onCancel: { scene.connectSheetModel = nil }
            )
        }
        .onAppear { installMouseNavMonitor() }
        .onDisappear { removeMouseNavMonitor() }
    }

    /// Mouse button 3 / 4 (the "Back" / "Forward" side buttons found on most
    /// external mice) route to the active tab's history. Wired via a local
    /// NSEvent monitor because NSView overrides only fire when the table is
    /// first responder — the user expects the side button to work everywhere
    /// in the window (breadcrumb, sidebar, preview pane, empty state).
    ///
    /// Button 3 is "back" on standard Mac mappings (Logitech, Razer, Apple's
    /// own USB Overdrive defaults). Button 4 is "forward". Returning the event
    /// unchanged for other buttons preserves middle-click and horizontal-wheel
    /// behaviour elsewhere; returning nil for 3/4 swallows it so it doesn't
    /// bubble to NSWindow as an unhandled click.
    private func installMouseNavMonitor() {
        guard mouseNavMonitor == nil else { return }
        mouseNavMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            switch event.buttonNumber {
            case 3:
                _ = tab?.goBack()
                return nil
            case 4:
                _ = tab?.goForward()
                return nil
            default:
                return event
            }
        }
    }

    private func removeMouseNavMonitor() {
        if let token = mouseNavMonitor {
            NSEvent.removeMonitor(token)
            mouseNavMonitor = nil
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

        // SSH connection state takes priority over folder state
        switch tab.connectionPhase {
        case .establishing(let alias):
            establishingView(alias: alias)
        case .connecting(let detail):
            connectingView(tab: tab, detail: detail)
        case .error(let title, let detail):
            remoteErrorView(tab: tab, title: title, detail: detail)
        default:
            // Local / idle / connected: existing logic
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
                if case .ssh = tab.provider.identifier {
                    remoteErrorView(tab: tab, title: "Listing failed", detail: msg)
                } else {
                    EmptyStateView.permissionDenied(message: msg) {
                        app.reopenFolder(startingAt: tab.currentFolder) { url in
                            if tab.currentFolder == url {
                                Task { await folder.load(url) }
                            } else {
                                tab.navigate(to: url)
                            }
                        }
                    }
                }
            } else {
                fileList(tab: tab)
            }
        }
    }

    @ViewBuilder
    private func establishingView(alias: String) -> some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Connecting to \(alias)")
                .font(.headline)
            Text("Negotiating SSH session — this can take a moment over ProxyCommand/Cloudflare.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func connectingView(tab: Tab, detail: String) -> some View {
        let hostname: String = {
            if let path = tab.currentPath, case .ssh(let t) = path.provider {
                return t.hostname
            }
            return "…"
        }()
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Connecting to \(hostname)")
                .font(.headline)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func remoteErrorView(tab: Tab, title: String, detail: String) -> some View {
        RemoteErrorCard(title: title, detail: detail, actions: remoteErrorActions(tab: tab, detail: detail))
    }

    private func remoteErrorActions(tab: Tab, detail: String) -> [RemoteErrorCard.Action] {
        var actions: [RemoteErrorCard.Action] = [
            .init(label: "Retry") { retrySSHTab(tab) },
            .init(label: "Edit ssh_config") { revealSshConfig() },
            .init(label: "Open Terminal") { openTerminalForTab(tab) },
        ]
        if detail.contains("ProxyCommand") || detail.contains("stderr:") {
            actions.append(.init(label: "Copy Error") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(detail, forType: .string)
            })
        }
        return actions
    }

    private func retrySSHTab(_ tab: Tab) {
        guard let path = tab.currentPath else { return }
        tab.connectionPhase = .connecting(detail: "Reconnecting…")
        tab.folder.clear()
        Task {
            await tab.folder.load(path, via: tab.provider)
            if case .failed(let msg) = tab.folder.state {
                tab.connectionPhase = .error(title: "Connection failed", detail: msg)
            } else {
                tab.connectionPhase = .connected
            }
        }
    }

    private func revealSshConfig() {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".ssh/config")
        NSWorkspace.shared.open(url)
    }

    private func openTerminalForTab(_ tab: Tab) {
        guard let path = tab.currentPath,
              case .ssh(let target) = path.provider else { return }
        var comps = URLComponents()
        comps.scheme = "ssh"
        comps.user = target.user
        comps.host = target.hostname
        if target.port != 22 { comps.port = Int(target.port) }
        if let url = comps.url {
            NSWorkspace.shared.open(url)
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
            showGitColumn: app.settings.showGitColumn,
            onActivate: { handleOpen($0, tab: tab) },
            onAddToPinned: handleAddToPinned,
            isPinnedCheck: { entry in
                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
            },
            onSelectionChanged: { handleSelectionChanged($0, tab: tab) },
            onMoved: {
                guard let path = tab.currentPath else { return }
                Task { await tab.folder.load(path, via: tab.provider) }
            },
            undoManager: tab.undoManager,
            provider: tab.provider,
            transfers: app.transfers,
            remoteProviderResolver: { [app] target in
                SshFileSystemProvider(pool: app.ssh, target: target, supportsServerSideCopy: false)
            }
        )
        .background {
            ZStack {
                VisualEffectBlur(material: .headerView)
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.18, blue: 0.32, opacity: 0.22),
                        Color(red: 0.06, green: 0.10, blue: 0.18, opacity: 0.12)
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
            TransferHudChip(controller: app.transfers)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: { showInspector.toggle() }) {
                Image(systemName: "sidebar.right")
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
                if let p = tab.currentPath { Task { await tab.folder.load(p, via: tab.provider) } }
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
            if case .ssh = tab.provider.identifier {
                let path = FSPath(provider: tab.provider.identifier, path: e.path.toString())
                tab.preview.setRemoteFocus(path, via: tab.provider)
            } else {
                tab.preview.focus = URL(fileURLWithPath: e.path.toString())
            }
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

    @MainActor
    private func performConnect(model: ConnectSheetModel) async {
        model.connecting = true
        model.error = nil
        defer { model.connecting = false }
        do {
            let (user, host) = model.resolveUserHost()

            if model.saveToConfig, !model.nickname.isEmpty {
                try app.sshConfig.appendHost(.init(
                    nickname: model.nickname,
                    hostname: host,
                    port: UInt16(model.port).flatMap { $0 == 22 ? nil : $0 },
                    user: user,
                    identityFile: model.authMode == .keyFile ? model.keyFile : nil,
                    proxyCommand: model.showAdvanced && !model.proxyCommand.isEmpty ? model.proxyCommand : nil
                ))
            }

            let alias = model.saveToConfig && !model.nickname.isEmpty ? model.nickname : host
            let overrides = ConnectSpecOverrides(
                user: user, port: UInt16(model.port),
                identityFile: model.authMode == .keyFile ? model.keyFile : nil,
                proxyCommand: model.showAdvanced && !model.proxyCommand.isEmpty ? model.proxyCommand : nil,
                password: model.authMode == .password && !model.password.isEmpty ? model.password : nil
            )
            let target = try await app.ssh.connect(hostAlias: alias, overrides: overrides)
            let provider = SshFileSystemProvider(pool: app.ssh, target: target, supportsServerSideCopy: false)
            // Resolve the initial path server-side. SFTP itself does not expand
            // "~" (that's a shell feature) — canonicalize(".") returns the
            // login user's home directory, which is what we want by default.
            let rawPath = model.path.isEmpty || model.path == "~" ? "." : model.path
            let resolvedPath = (try? await provider.realpath(rawPath)) ?? rawPath
            let initial = FSPath(provider: .ssh(target), path: resolvedPath)
            scene.newRemoteTab(initialPath: initial, provider: provider)
            if let newTab = scene.activeTab {
                newTab.connectionPhase = .connected
            }
            // Persist the password under the ssh_config nickname so a later
            // sidebar click can silently re-connect via Keychain lookup.
            if model.authMode == .password,
               model.saveToConfig,
               !model.nickname.isEmpty,
               !model.password.isEmpty {
                KeychainPasswordStore.save(model.password, for: model.nickname)
            }
            scene.connectSheetModel = nil
        } catch {
            // Only surface the error if the sheet is still visible (user didn't cancel mid-flight)
            if scene.connectSheetModel != nil {
                model.error = ErrorMessage.userFacing(error)
            }
        }
    }
}
