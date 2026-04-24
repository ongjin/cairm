import SwiftUI

/// Path segments for the current folder, rendered as clickable buttons.
/// Collapses the user's home prefix to "~" so `~/Documents` shows as
/// `~ › Documents` instead of `Macintosh › Users › cyj › Documents`.
///
/// SSH paths get the same treatment against `/home/<sshuser>` (or `/root`
/// when connecting as root), and the `ssh://user@host` preamble is lifted
/// into a tinted chip so the path segments stay readable in narrow panes.
/// Everything is wrapped in a horizontal ScrollView so a deep remote path
/// never forces a two-line wrap when the window is split.
struct BreadcrumbBar: View {
    let tab: Tab?

    /// Cached once — `Host.current().localizedName` is a configd IPC round-trip.
    static let computerName: String = Host.current().localizedName ?? "Computer"

    /// Teal accent reused by the SSH host chip — matches the existing
    /// `ssh://` color to keep visual continuity with the rest of the app.
    private static let sshAccent = Color(red: 0.55, green: 0.85, blue: 0.73)

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        Group {
            if let tab {
                if case .ssh(let target) = tab.currentPath?.provider {
                    sshBar(target: target, path: tab.currentPath?.path ?? "/")
                } else if let current = tab.currentFolder {
                    localBar(tab: tab, current: current)
                }
            }
        }
    }

    // MARK: - SSH

    private func sshBar(target: SshTarget, path: String) -> some View {
        let parts = Self.sshSegments(path: path, user: target.user)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                sshHostChip(target: target)
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { idx, seg in
                        // Chevron always leads each segment since the host
                        // chip renders just left of them.
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(seg)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .foregroundStyle(idx == parts.count - 1 ? Color.primary : Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func sshHostChip(target: SshTarget) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "network")
                .font(.system(size: 9, weight: .semibold))
            Text("\(target.user)@\(target.hostname)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundStyle(Self.sshAccent)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Self.sshAccent.opacity(0.13)))
        .overlay(Capsule().strokeBorder(Self.sshAccent.opacity(0.35), lineWidth: 0.5))
        .help("ssh://\(target.user)@\(target.hostname):\(target.port)")
    }

    // MARK: - Local

    private func localBar(tab: Tab, current: URL) -> some View {
        let segs = Self.segments(for: current, home: Self.home)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(segs.enumerated()), id: \.offset) { pair in
                    let (i, seg) = pair
                    Button(seg.label) { tab.navigate(to: seg.url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(i == segs.count - 1 ? Color.primary : Color.secondary)
                    if i < segs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Segment helpers (visible for tests)

    /// Visible for tests. Produces rendered path segments for an SSH path,
    /// collapsing `/home/<user>` (or `/root` when user == "root") to `~` so
    /// remote breadcrumbs don't waste two segments on a well-known prefix.
    static func sshSegments(path: String, user: String) -> [String] {
        let homePrefix = user == "root" ? "/root" : "/home/\(user)"
        if path == homePrefix {
            return ["~"]
        }
        if path.hasPrefix(homePrefix + "/") {
            let rest = String(path.dropFirst(homePrefix.count + 1))
            return ["~"] + rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        }
        return path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    /// Visible for tests. Produces the rendered (label, url) tuples.
    /// Inside `$HOME`: leading segment is `~` pointing at `$HOME`.
    /// Elsewhere: leading segment is the computer name pointing at `/`.
    static func segments(for url: URL, home: URL) -> [(label: String, url: URL)] {
        let std = url.standardizedFileURL
        let homeStd = home.standardizedFileURL

        if std.path == homeStd.path {
            return [("~", homeStd)]
        }

        let homeComponents = homeStd.pathComponents
        let urlComponents = std.pathComponents
        let insideHome =
            urlComponents.count > homeComponents.count &&
            Array(urlComponents.prefix(homeComponents.count)) == homeComponents

        if insideHome {
            var out: [(String, URL)] = [("~", homeStd)]
            var accum = homeStd
            for c in urlComponents.dropFirst(homeComponents.count) {
                accum = accum.appendingPathComponent(c)
                out.append((c, accum))
            }
            return out
        }

        var out: [(String, URL)] = [(computerName, URL(fileURLWithPath: "/"))]
        var accum = URL(fileURLWithPath: "/")
        for (i, c) in urlComponents.enumerated() where i > 0 {
            accum = accum.appendingPathComponent(c)
            out.append((c, accum))
        }
        return out
    }
}
