import SwiftUI
import AppKit

/// Renders one pane's content — tab bar, inline back/forward/up + breadcrumb
/// strip, file list with all its empty/error/connecting states. Takes the
/// pane's `WindowSceneModel` explicitly so the same view can be used for
/// both the left pane (always present) and the right pane (created on
/// ⌘⇧D split).
///
/// Extracted from `ContentView.detailColumn` when dual-pane landed; the
/// rendering logic is unchanged, just parameterised on `scene` instead of
/// reading it from `@Environment`.
struct PaneColumn: View {
    @Environment(AppModel.self) private var app
    @Environment(\.cairnTheme) private var theme

    @Bindable var scene: WindowSceneModel
    let isActive: Bool
    let onFocus: () -> Void

    /// Pane frame in SwiftUI global (= window content-area, top-left
    /// origin) coordinates. Captured via GeometryReader in `.background`
    /// and consulted by the NSEvent mouse-down monitor to route pane-focus
    /// without depending on SwiftUI gestures firing — NSTableView-backed
    /// file list swallows clicks before `simultaneousGesture` runs, and
    /// selection-change onChange misses clicks on the already-selected row.
    /// The monitor converts AppKit `event.locationInWindow` into the same
    /// coordinate space before the contains() check.
    @State private var frameInWindow: CGRect = .zero
    @State private var mouseDownMonitor: Any?
    /// Host NSWindow captured via WindowAccessor. The click-to-focus monitor
    /// is application-wide (NSEvent.addLocalMonitorForEvents), so we gate
    /// every event on `event.window === hostWindow` — otherwise clicks in
    /// window A can flip activeSide in window B if their pane frames overlap.
    @State private var hostWindow: NSWindow?

    private var tab: Tab? { scene.activeTab }

    var body: some View {
        paneStack
            .opacity(isActive ? 1.0 : 0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frameInWindow = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, new in
                            frameInWindow = new
                        }
                }
            )
            .background(WindowAccessor(window: $hostWindow))
            .onAppear { installMouseDownMonitor() }
            .onDisappear { removeMouseDownMonitor() }
            .task {
                if let tab, let path = tab.currentPath {
                    await tab.folder.load(path, via: tab.provider)
                }
            }
            .onChange(of: tab?.currentPath) { old, new in
                guard let tab else { return }
                guard let path = new else { tab.folder.clear(); return }
                if case .local = path.provider {
                    app.lastFolder.save(URL(fileURLWithPath: path.path))
                }
                if old == path, tab.folder.currentPath == path, tab.folder.state == .loaded {
                    return
                }
                Task { await tab.folder.load(path, via: tab.provider) }
            }
            .onChange(of: scene.activeTabID) { _, _ in
                onFocus()
                // `tab?.currentPath` above reloads when the newly-active tab's
                // path *differs* from the old one. But SwiftUI's onChange is
                // value-equality — if two tabs happen to share the same path
                // (e.g. ⌘T clone → both on ~/Downloads) currentPath is
                // unchanged across the swap and that onChange never fires,
                // leaving the fresh tab's FolderModel blank until the user
                // manually refreshes. Reload here only when the newly-active
                // tab hasn't loaded the target yet; don't re-list when it
                // already has entries for this path.
                guard let tab, let path = tab.currentPath else { return }
                if tab.folder.currentPath == path, tab.folder.state == .loaded {
                    return
                }
                Task { await tab.folder.load(path, via: tab.provider) }
            }
            .onChange(of: app.showHidden) { _, _ in
                if let tab, let path = tab.currentPath {
                    Task { await tab.folder.load(path, via: tab.provider) }
                }
            }
            .sheet(item: Bindable(scene).connectSheetModel) { model in
                ConnectSheetView(
                    model: model,
                    onConnect: { Task { await performConnect(model: model) } },
                    onCancel: { scene.connectSheetModel = nil }
                )
            }
    }

    // Extracted so the main `body` chain stays short enough for the type
    // checker — previously this tripped the "unable to type-check in
    // reasonable time" limit with ~9 chained modifiers on a VStack literal.
    private var paneStack: some View {
        VStack(spacing: 0) {
            TabBarView(scene: scene)
            inlineNavStrip
            contentColumn
        }
    }

    // MARK: - Click-to-focus (NSEvent mouse-down monitor)

    private func installMouseDownMonitor() {
        guard mouseDownMonitor == nil else { return }
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            // Local event monitors are app-wide. Hard-gate on host window
            // identity — otherwise clicks in another window whose pane
            // frame coordinates collide with ours would silently flip
            // activeSide on the wrong window.
            guard let eventWindow = event.window,
                  let host = hostWindow,
                  eventWindow === host,
                  let contentView = eventWindow.contentView else { return event }
            // Bridge AppKit window coords (bottom-left origin, Y up) to
            // SwiftUI global coords (top-left origin, Y down) so the
            // contains() check lines up with the frame GeometryReader
            // reports. Convert window → contentView first to strip any
            // titlebar offset, then flip Y against contentView height.
            let contentPoint = contentView.convert(event.locationInWindow, from: nil)
            let swiftUIPoint = CGPoint(
                x: contentPoint.x,
                y: contentView.frame.height - contentPoint.y
            )
            if frameInWindow.contains(swiftUIPoint) {
                onFocus()
            }
            return event
        }
    }

    private func removeMouseDownMonitor() {
        if let token = mouseDownMonitor {
            NSEvent.removeMonitor(token)
            mouseDownMonitor = nil
        }
    }

    // MARK: - Inline nav strip (was in the window toolbar pre-dual-pane)

    @ViewBuilder
    private var inlineNavStrip: some View {
        HStack(spacing: 6) {
            Button(action: { _ = tab?.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!(tab?.history.canGoBack ?? false))

            Button(action: { _ = tab?.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(!(tab?.history.canGoForward ?? false))

            Button(action: { tab?.goUp() }) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)

            BreadcrumbBar(tab: tab)

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.12))
    }

    // MARK: - Content body (delegates to the connection-phase / folder-state dispatch)

    @ViewBuilder
    private var contentColumn: some View {
        if let tab {
            VStack(spacing: 0) {
                if tab.search.phase == .capped {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(tab.search.hitCount.formatted())+ results (capped, narrow your query)")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                PaneContentBody(
                    app: app,
                    scene: scene,
                    tab: tab,
                    theme: theme
                )
            }
            .animation(.easeInOut(duration: 0.2), value: tab.search.phase)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    // MARK: - Connect sheet flow (kept in sync with ContentView.performConnect)

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
            let rawPath = model.path.isEmpty || model.path == "~" ? "." : model.path
            let resolvedPath = (try? await provider.realpath(rawPath)) ?? rawPath
            let initial = FSPath(provider: .ssh(target), path: resolvedPath)
            scene.newRemoteTab(initialPath: initial, provider: provider)
            if let newTab = scene.activeTab {
                newTab.connectionPhase = .connected
            }
            if model.authMode == .password,
               model.saveToConfig,
               !model.nickname.isEmpty,
               !model.password.isEmpty {
                KeychainPasswordStore.save(model.password, for: model.nickname)
            }
            scene.connectSheetModel = nil
        } catch {
            if scene.connectSheetModel != nil {
                model.error = ErrorMessage.userFacing(error)
            }
        }
    }
}

/// Pulled out as its own view so `@ViewBuilder` switch / if-else remains
/// manageable. Handles the connection-phase dispatch (establishing →
/// connecting → error → folder state → fileList).
private struct PaneContentBody: View {
    let app: AppModel
    let scene: WindowSceneModel
    let tab: Tab
    let theme: CairnTheme

    var body: some View {
        let folder = tab.folder
        let searchModel = tab.search

        switch tab.connectionPhase {
        case .establishing(let alias):
            establishingView(alias: alias)
        case .connecting(let detail):
            connectingView(detail: detail)
        case .error(let title, let detail):
            remoteErrorView(title: title, detail: detail)
        default:
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
                    remoteErrorView(title: "Listing failed", detail: msg)
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
                fileList
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
    private func connectingView(detail: String) -> some View {
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

    private func remoteErrorView(title: String, detail: String) -> some View {
        RemoteErrorCard(title: title, detail: detail, actions: remoteErrorActions(detail: detail))
    }

    private func remoteErrorActions(detail: String) -> [RemoteErrorCard.Action] {
        var actions: [RemoteErrorCard.Action] = [
            .init(label: "Retry") { retry() },
            .init(label: "Edit ssh_config") { revealSshConfig() },
            .init(label: "Open Terminal") { openTerminal() },
        ]
        if detail.contains("ProxyCommand") || detail.contains("stderr:") {
            actions.append(.init(label: "Copy Error") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(detail, forType: .string)
            })
        }
        return actions
    }

    private func retry() {
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

    private func openTerminal() {
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

    private var fileList: some View {
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
            onActivate: { handleOpen($0) },
            onAddToPinned: { entry in
                guard entry.kind == .Directory else { return }
                let url = URL(fileURLWithPath: entry.path.toString())
                try? app.bookmarks.togglePin(url: url)
            },
            isPinnedCheck: { entry in
                app.bookmarks.isPinned(url: URL(fileURLWithPath: entry.path.toString()))
            },
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

    private func handleOpen(_ entry: FileEntry) {
        let pathStr = entry.path.toString()
        if entry.kind == .Directory {
            let fsPath = FSPath(provider: tab.provider.identifier, path: pathStr)
            tab.navigate(to: fsPath)
        } else {
            if case .ssh = tab.provider.identifier { return }
            NSWorkspace.shared.open(URL(fileURLWithPath: pathStr))
        }
    }

}
