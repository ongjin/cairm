import SwiftUI
import AppKit

/// Finder-parity sidebar: Favorites (auto + pinned) / Cloud / Remote Hosts / Locations (Home + AirDrop + Network + Trash).
/// Footer shows active tab's git branch + dirty count when in a repo.
struct SidebarView: View {
    @Bindable var app: AppModel
    @Bindable var scene: WindowSceneModel
    @Environment(\.cairnTheme) private var theme

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
                            onActivate: { scene.activeTab?.navigate(to: fav.url) }
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

                let remoteHosts = app.sidebar.remoteHostItems(from: app.sshConfig, pool: app.ssh)
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
                        onActivate: { scene.activeTab?.navigate(to: home) }
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
                            let selected = scene.activeTab?.folder.selection ?? []
                            let urls = selected.map { URL(fileURLWithPath: $0) }
                            if urls.isEmpty {
                                NSSound.beep()
                            } else {
                                NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
                            }
                        }

                    // Network
                    let network = URL(fileURLWithPath: "/Network")
                    row(url: network, icon: "network", label: "Network", tint: nil, canPin: false)

                    // Trash
                    let trash = home.appendingPathComponent(".Trash")
                    SidebarItemRow(icon: "trash", label: "Trash", tint: nil, isSelected: isCurrent(trash))
                        .contentShape(Rectangle())
                        .onTapGesture { scene.activeTab?.navigate(to: trash) }
                        .contextMenu {
                            Button("Empty Trash") {
                                let fm = FileManager.default
                                if let items = try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
                                    for u in items { try? fm.trashItem(at: u, resultingItemURL: nil) }
                                }
                            }
                        }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            if let snap = scene.activeTab?.git?.snapshot, let branch = snap.branch {
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
        .onTapGesture { scene.activeTab?.navigate(to: entry) }
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
            .onTapGesture { scene.activeTab?.navigate(to: url) }
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
        guard let current = scene.activeTab?.currentFolder else { return false }
        return url.standardizedFileURL.path == current.standardizedFileURL.path
    }

    // MARK: - Remote host helpers

    /// Tap on a sidebar remote host. If a Keychain password exists for this
    /// alias, attempt a silent reconnect; fall through to the sheet on failure
    /// or when no saved password is found. This keeps password hosts behaving
    /// like agent/key hosts (single click → tab opens), without burying the
    /// sheet-based recovery path for stale credentials.
    private func connectHost(_ name: String) {
        if let saved = KeychainPasswordStore.load(for: name) {
            Task { await attemptSilentConnect(alias: name, password: saved) }
            return
        }
        let model = ConnectSheetModel()
        model.server = name  // pre-fill from sidebar connect tap
        scene.connectSheetModel = model
    }

    @MainActor
    private func attemptSilentConnect(alias: String, password: String) async {
        do {
            let overrides = ConnectSpecOverrides(password: password)
            let target = try await app.ssh.connect(hostAlias: alias, overrides: overrides)
            let provider = SshFileSystemProvider(pool: app.ssh, target: target, supportsServerSideCopy: false)
            let resolvedPath = (try? await provider.realpath(".")) ?? "/"
            let initial = FSPath(provider: .ssh(target), path: resolvedPath)
            scene.newRemoteTab(initialPath: initial, provider: provider)
            scene.activeTab?.connectionPhase = .connected
        } catch {
            // Silent attempt failed — surface the sheet with nickname pre-filled
            // so the user can correct the password. Keychain entry is left as
            // is; the PasswordResolver alert will overwrite it on re-auth.
            let model = ConnectSheetModel()
            model.server = alias
            model.authMode = .password
            model.error = ErrorMessage.userFacing(error)
            scene.connectSheetModel = model
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
        scene.connectSheetModel = ConnectSheetModel()
    }
}
