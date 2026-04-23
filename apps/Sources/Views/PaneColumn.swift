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

    private var tab: Tab? { scene.activeTab }

    var body: some View {
        paneStack
            .opacity(isActive ? 1.0 : 0.72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Pane focus: plain `.onTapGesture` doesn't fire when the click
            // lands inside the NSTableView-backed file list (AppKit swallows
            // the event). `simultaneousGesture` runs alongside the child's
            // handling. We also auto-focus on selection change or tab switch
            // inside the pane — any interaction inside this side = "this
            // side is active".
            .simultaneousGesture(TapGesture().onEnded { onFocus() })
            .onChange(of: tab?.folder.selection) { _, _ in onFocus() }
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
            }
            .onChange(of: scene.activeTabID) { _, _ in
                onFocus()
                guard let tab, let path = tab.currentPath else { return }
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
                        Text("Showing first 5,000 results — refine your query")
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
            onSelectionChanged: { handleSelectionChanged($0) },
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

    private func handleSelectionChanged(_ entry: FileEntry?) {
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
}
