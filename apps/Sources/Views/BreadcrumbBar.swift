import SwiftUI

/// Path segments for the current folder, rendered as clickable buttons.
/// Collapses the user's home prefix to "~" so `~/Documents` shows as
/// `~ › Documents` instead of `Macintosh › Users › cyj › Documents`.
struct BreadcrumbBar: View {
    let tab: Tab?

    /// Cached once — `Host.current().localizedName` is a configd IPC round-trip.
    static let computerName: String = Host.current().localizedName ?? "Computer"

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        if let tab, let current = tab.currentFolder {
            let segs = Self.segments(for: current, home: Self.home)
            HStack(spacing: 2) {
                ForEach(Array(segs.enumerated()), id: \.offset) { pair in
                    let (i, seg) = pair
                    Button(seg.label) { tab.navigate(to: seg.url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(i == segs.count - 1 ? Color.primary : Color.secondary)
                    if i < segs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
        }
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
