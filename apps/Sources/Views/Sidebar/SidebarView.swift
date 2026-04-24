import SwiftUI
import AppKit

/// Finder-parity sidebar: Favorites (auto + pinned) / Cloud / Remote Hosts / Locations (Home + AirDrop).
/// Footer shows active tab's git branch + dirty count when in a repo.
struct SidebarView: View {
    @Bindable var app: AppModel
    @Environment(WindowDualPaneModel.self) private var dualPane
    @Environment(\.cairnTheme) private var theme

    /// Sidebar clicks always target the currently-focused pane (left or
    /// right). Computed at render time so the pane dot state and navigation
    /// both track `dualPane.activeSide` without a cached copy getting stale.
    private var activeScene: WindowSceneModel { dualPane.activePane }

    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var autoFavorites: [(icon: String, label: String, url: URL)] {
        [
            ("app.badge", "Applications", URL(fileURLWithPath: "/Applications")),
            ("menubar.dock.rectangle", "Desktop", home.appendingPathComponent("Desktop")),
            ("doc", "Documents", home.appendingPathComponent("Documents")),
            ("arrow.down.circle", "Downloads", home.appendingPathComponent("Downloads")),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section("Favorites") {
                    ForEach(autoFavorites, id: \.url) { fav in
                        SidebarAutoFavoriteRow(
                            icon: fav.icon,
                            label: fav.label,
                            url: fav.url,
                            isSelected: isCurrent(fav.url),
                            onActivate: {
                                guard let tab = activeScene.activeTab else { return }
                                app.openAutoFavorite(url: fav.url, in: tab)
                            }
                        )
                    }
                    ForEach(app.bookmarks.pinned) { entry in
                        pinnedRow(entry)
                    }
                }

                if let iCloud = app.sidebar.iCloudURL {
                    Section("Cloud") {
                        row(url: iCloud,
                            icon: "icloud",
                            label: "iCloud Drive",
                            tint: .blue,
                            canPin: true)
                    }
                }

                let remoteHosts = app.sidebar.remoteHostItems(
                    from: app.sshConfig,
                    pool: app.ssh,
                    usedTargets: app.usedSshTargets
                )
                if !remoteHosts.isEmpty || true {  // always show section (empty state shows + button)
                    Section(header: Text("Remote Hosts").font(.system(size: 11)).foregroundStyle(.secondary)) {
                        ForEach(remoteHosts, id: \.id) { item in
                            RemoteHostRow(
                                item: item,
                                onConnect: { connectHost(item.id) },
                                onDisconnect: { disconnectHost(item.id) },
                                onHide: { hideHost(item.id) },
                                onRevealConfig: { revealConfig() },
                                onCopySshCommand: { copySshCommand(item.id) }
                            )
                        }
                        Button {
                            openConnectSheet()
                        } label: {
                            Label("Connect\u{2026}", systemImage: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Locations") {
                    // Home
                    SidebarAutoFavoriteRow(
                        icon: "house",
                        label: NSUserName(),
                        url: home,
                        isSelected: isCurrent(home),
                        onActivate: {
                            guard let tab = activeScene.activeTab else { return }
                            app.openAutoFavorite(url: home, in: tab)
                        }
                    )

                    ForEach(app.sidebar.locations, id: \.self) { loc in
                        row(url: loc,
                            icon: loc.path == "/" ? "desktopcomputer" : "externaldrive",
                            label: locationLabel(loc),
                            tint: nil,
                            canPin: true)
                    }

                    // AirDrop — sends current selection; beeps if nothing selected.
                    SidebarItemRow(icon: "dot.radiowaves.up.forward", label: "AirDrop", tint: nil, isSelected: false)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let selected = activeScene.activeTab?.folder.selection ?? []
                            let urls = selected.map { URL(fileURLWithPath: $0) }
                            if urls.isEmpty {
                                NSSound.beep()
                            } else {
                                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if let snap = activeScene.activeTab?.git?.snapshot, let branch = snap.branch {
                GitBranchFooter(branch: branch, dirtyCount: snap.dirtyCount)
            }
        }
        .background {
            ZStack {
                VisualEffectBlur(material: .sidebar)
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.35, blue: 0.60, opacity: 0.50),
                        Color(red: 0.10, green: 0.18, blue: 0.35, opacity: 0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 200)
    }

    // MARK: - Rows (existing helpers, kept intact)

    private func pinnedRow(_ entry: BookmarkEntry) -> some View {
        let url = URL(fileURLWithPath: entry.lastKnownPath)
        return SidebarItemRow(
            icon: "pin.fill",
            label: entry.label ?? url.lastPathComponent,
            tint: .orange,
            isSelected: isCurrent(url)
        )
        .contentShape(Rectangle())
        .onTapGesture { activeScene.activeTab?.navigate(to: entry) }
        .contextMenu {
            Button("Unpin") { app.bookmarks.unpin(entry) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.lastKnownPath,
                                              inFileViewerRootedAtPath: "")
            }
        }
    }

    private func row(url: URL, icon: String, label: String, tint: Color?, canPin: Bool) -> some View {
        SidebarItemRow(icon: icon, label: label, tint: tint, isSelected: isCurrent(url))
            .contentShape(Rectangle())
            .onTapGesture { activeScene.activeTab?.navigate(to: url) }
            .contextMenu {
                if canPin {
                    if app.bookmarks.isPinned(url: url) {
                        Button("Unpin") { try? app.bookmarks.togglePin(url: url) }
                    } else {
                        Button("Add to Pinned") { try? app.bookmarks.togglePin(url: url) }
                    }
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(url.path,
                                                  inFileViewerRootedAtPath: "")
                }
            }
    }

    private func locationLabel(_ url: URL) -> String {
        if url.path == "/" {
            return Host.current().localizedName ?? "Computer"
        }
        return url.lastPathComponent
    }

    /// Compare against the active tab's `currentFolder` using the standardized
    /// path form so `/tmp/foo` and `/private/tmp/foo` and `/tmp/./foo` all
    /// match one another.
    private func isCurrent(_ url: URL) -> Bool {
        guard let current = activeScene.activeTab?.currentFolder else { return false }
        return url.standardizedFileURL.path == current.standardizedFileURL.path
    }

    // MARK: - Remote host helpers

    /// Tap on a sidebar remote host. Opens a placeholder tab in the
    /// `.establishing` phase immediately (so the user sees "Connecting to
    /// <alias>…" rather than a frozen sidebar), then negotiates the SSH
    /// session in the background. On success the placeholder upgrades into a
    /// real remote tab; on failure it flips to `.error` which renders the
    /// existing RemoteErrorCard (Retry / Edit ssh_config / Open Terminal).
    private func connectHost(_ name: String) {
        let savedPassword = KeychainPasswordStore.load(for: name)
        let placeholder = activeScene.newEstablishingTab(alias: name)
        Task { await attemptSilentConnect(alias: name, password: savedPassword, placeholder: placeholder) }
    }

    @MainActor
    private func attemptSilentConnect(alias: String, password: String?, placeholder: Tab) async {
        let pane = activeScene
        do {
            let overrides = ConnectSpecOverrides(password: password)
            let target = try await app.ssh.connect(hostAlias: alias, overrides: overrides)
            let provider = SshFileSystemProvider(pool: app.ssh, target: target, supportsServerSideCopy: false)
            let resolvedPath = (try? await provider.realpath(".")) ?? "/"
            let initial = FSPath(provider: .ssh(target), path: resolvedPath)
            placeholder.upgradeToRemote(path: initial, provider: provider)
            // Prime the remote listing ourselves rather than letting the
            // onChange(currentPath) hop do it — keeps the spinner on screen
            // continuously until data is on the table.
            await placeholder.folder.load(initial, via: provider)
            placeholder.connectionPhase = .connected
        } catch {
            // Placeholder tab can't retry on its own (no target/provider yet
            // and no ssh_config round-trip past here). Close it and surface
            // the Connect sheet with the alias + error so the user can fix
            // credentials or tweak ssh_config and try again.
            pane.closeTab(placeholder.id)
            let model = ConnectSheetModel()
            model.server = alias
            if password != nil {
                model.authMode = .password
            }
            model.error = ErrorMessage.userFacing(error)
            pane.connectSheetModel = model
        }
    }

    private func disconnectHost(_ name: String) {
        Task { @MainActor in
            if let target = app.ssh.sessions.keys.first(where: { $0.hostname == name }) {
                app.ssh.disconnect(target)
            }
        }
    }

    private func hideHost(_ name: String) {
        app.sshConfig.hideHost(name)
    }

    private func revealConfig() {
        guard let home = ProcessInfo.processInfo.environment["HOME"] else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(home)/.ssh/config"))
    }

    private func copySshCommand(_ name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ssh \(name)", forType: .string)
    }

    private func openConnectSheet() {
        activeScene.connectSheetModel = ConnectSheetModel()
    }
}
