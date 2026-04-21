import SwiftUI
import AppKit

/// Finder-like 4-section sidebar: Pinned / Recent / iCloud Drive / Locations.
/// Clicking an item navigates via AppModel. Right-click gives "Add to Pinned",
/// "Unpin", or "Reveal in Finder" depending on the item's section. The row that
/// matches the current folder gets a theme-accented highlight.
struct SidebarView: View {
    @Bindable var app: AppModel
    @Environment(\.cairnTheme) private var theme

    var body: some View {
        List {
            if !app.bookmarks.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(app.bookmarks.pinned) { entry in
                        pinnedRow(entry)
                    }
                }
            }

            if !app.bookmarks.recent.isEmpty {
                Section("Recent") {
                    ForEach(app.bookmarks.recent) { entry in
                        recentRow(entry)
                    }
                }
            }

            if let iCloud = app.sidebar.iCloudURL {
                Section("iCloud") {
                    row(url: iCloud,
                        icon: "icloud",
                        label: "iCloud Drive",
                        tint: .blue,
                        canPin: true)
                }
            }

            Section("Locations") {
                ForEach(app.sidebar.locations, id: \.self) { loc in
                    row(url: loc,
                        icon: loc.path == "/" ? "desktopcomputer" : "externaldrive",
                        label: locationLabel(loc),
                        tint: nil,
                        canPin: true)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background {
            ZStack {
                VisualEffectBlur(material: .sidebar)
                theme.sidebarTint.opacity(0.4)
            }
            .ignoresSafeArea()
        }
        .frame(minWidth: 200)
    }

    // MARK: - Rows

    private func pinnedRow(_ entry: BookmarkEntry) -> some View {
        let url = URL(fileURLWithPath: entry.lastKnownPath)
        return SidebarItemRow(
            icon: "pin.fill",
            label: entry.label ?? url.lastPathComponent,
            tint: .orange,
            isSelected: isCurrent(url)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.navigate(to: entry) }
        .contextMenu {
            Button("Unpin") { app.bookmarks.unpin(entry) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.lastKnownPath,
                                              inFileViewerRootedAtPath: "")
            }
        }
    }

    private func recentRow(_ entry: BookmarkEntry) -> some View {
        let url = URL(fileURLWithPath: entry.lastKnownPath)
        return SidebarItemRow(
            icon: "clock",
            label: url.lastPathComponent,
            tint: nil,
            isSelected: isCurrent(url)
        )
        .contentShape(Rectangle())
        .onTapGesture { app.navigate(to: entry) }
        .contextMenu {
            Button("Add to Pinned") { try? app.bookmarks.togglePin(url: URL(fileURLWithPath: entry.lastKnownPath)) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(entry.lastKnownPath,
                                              inFileViewerRootedAtPath: "")
            }
        }
    }

    private func row(url: URL, icon: String, label: String, tint: Color?, canPin: Bool) -> some View {
        SidebarItemRow(icon: icon, label: label, tint: tint, isSelected: isCurrent(url))
            .contentShape(Rectangle())
            .onTapGesture { app.navigateUnscoped(to: url) }
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

    /// Compare against `app.currentFolder` using the standardized path form so
    /// `/tmp/foo` and `/private/tmp/foo` and `/tmp/./foo` all match one another.
    private func isCurrent(_ url: URL) -> Bool {
        guard let current = app.currentFolder else { return false }
        return url.standardizedFileURL.path == current.standardizedFileURL.path
    }
}
