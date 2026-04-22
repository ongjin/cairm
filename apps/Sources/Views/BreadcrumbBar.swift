import SwiftUI

/// Path segments for the current folder, rendered as clickable buttons.
/// Lives inside ContentView's toolbar. "Computer" slash is represented as a
/// single leading "/" segment.
///
/// Takes an optional `Tab` directly — the eventual T12 call site will pass
/// `scene.activeTab`. A nil tab hides the bar entirely (no window yet, or
/// all tabs closed mid-transition).
struct BreadcrumbBar: View {
    let tab: Tab?

    /// Cached once — `Host.current().localizedName` is a configd IPC round-trip.
    private static let computerName: String = Host.current().localizedName ?? "Computer"

    var body: some View {
        if let tab, let current = tab.currentFolder {
            let segs = segments(for: current)
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

    private func segments(for url: URL) -> [(label: String, url: URL)] {
        var out: [(String, URL)] = []
        let components = url.standardizedFileURL.pathComponents
        var accum = URL(fileURLWithPath: "/")
        for (i, c) in components.enumerated() {
            if i == 0 { continue } // first is "/"
            accum = accum.appendingPathComponent(c)
            out.append((c, accum))
        }
        out.insert((Self.computerName, URL(fileURLWithPath: "/")), at: 0)
        return out
    }
}
